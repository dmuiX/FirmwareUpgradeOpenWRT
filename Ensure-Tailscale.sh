#!/bin/sh
# Restore missing Tailscale packages after sysupgrade without changing installed packages.
set -eu
umask 077

CHECK_ONLY=0
case "${1:-}" in
  --check) CHECK_ONLY=1 ;;
  --non-interactive|'') ;;
  *) echo "Usage: $0 [--check|--non-interactive]" >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || exit 2

fail() { echo "ERROR: $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || fail "Run as root."
for tool in apk awk cmp grep sed uname; do command -v "$tool" >/dev/null || fail "Required command unavailable: $tool"; done

ROM_REPOSITORIES=/rom/etc/apk/repositories.d/distfeeds.list
ROM_KEYS=/rom/etc/apk/keys
kernel_version() {
  apk "$@" query --fields version --format yaml --installed kernel | sed -n 's/^- version: //p'
}
release_version() {
  sed -n "s/^DISTRIB_RELEASE='\([^']*\)'$/\1/p" "$1"
}

running_kernel=$(uname -r)
rom_kernel=$(kernel_version --root /rom)
installed_kernel=$(kernel_version)
[ -n "$rom_kernel" ] && [ "$installed_kernel" = "$rom_kernel" ] || fail "Kernel package metadata differs from /rom."
case "$rom_kernel" in "$running_kernel"~*|"$running_kernel"-r*) ;; *) fail "Running kernel differs from /rom." ;; esac
active_release=$(release_version /etc/openwrt_release)
rom_release=$(release_version /rom/etc/openwrt_release)
[ -n "$active_release" ] && [ -n "$rom_release" ] || fail "Release metadata is empty."
[ "$active_release" = "$rom_release" ] || fail "Release metadata differs from /rom."
cmp -s /etc/apk/repositories.d/distfeeds.list "$ROM_REPOSITORIES" || fail "Distribution feeds differ from /rom."
[ -r "$ROM_REPOSITORIES" ] && [ -d "$ROM_KEYS" ] || fail "Firmware repositories or keys are unavailable."

[ "$CHECK_ONLY" -eq 0 ] || { echo "Firmware metadata is coherent. No changes made."; exit 0; }

lock=/var/lock/post-sysupgrade-package-install.lock
attempt=0
while ! mkdir "$lock" 2>/dev/null; do
  [ "$attempt" -lt 60 ] || fail "Package restoration lock remained busy."
  attempt=$((attempt + 1))
  sleep 2
done
trap 'rmdir "$lock"' EXIT
trap 'exit 1' HUP INT TERM

module_present() {
  [ -f "/lib/modules/$running_kernel/tun.ko" ] ||
    [ -f "/lib/modules/$running_kernel/tun.ko.gz" ] ||
    [ -f "/lib/modules/$running_kernel/tun.ko.zst" ]
}

missing=
if apk info -e tailscale >/dev/null 2>&1; then
  command -v tailscaled >/dev/null 2>&1 || fail "Tailscale is installed but tailscaled is missing."
else
  command -v tailscaled >/dev/null 2>&1 && fail "tailscaled exists without package metadata."
  missing=tailscale
fi
if apk info -e kmod-tun >/dev/null 2>&1; then
  module_present || fail "kmod-tun is installed but its module is missing."
else
  module_present && fail "TUN module exists without package metadata."
  missing="${missing:+$missing }kmod-tun"
fi
if [ -n "$missing" ]; then
  apk --wait 120 --keys-dir "$ROM_KEYS" --repositories-file "$ROM_REPOSITORIES" update || fail "Package index update failed."
  # No other package-management process runs on this router. The shared lock
  # serializes both restoration scripts between this check and installation.
  # shellcheck disable=SC2086
  plan=$(apk --wait 120 --keys-dir "$ROM_KEYS" --repositories-file "$ROM_REPOSITORIES" add --simulate $missing 2>&1) || fail "Cannot calculate package plan."
  changes=$(printf '%s\n' "$plan" | grep -E '^\([[:space:]]*[0-9]+/[0-9]+\) ' || true)
  [ -n "$changes" ] || fail "Package plan contains no changes."
  printf '%s\n' "$changes" | grep -Ev '^\([[:space:]]*[0-9]+/[0-9]+\) Installing [^[:space:]]+ \(' >/dev/null && fail "Package plan would change an installed package."
  for package in $missing; do
    printf '%s\n' "$changes" | grep -Eq "^\\([[:space:]]*[0-9]+/[0-9]+\\) Installing $package \\(" || fail "Package plan does not install $package."
  done
  # shellcheck disable=SC2086
  apk --wait 120 --keys-dir "$ROM_KEYS" --repositories-file "$ROM_REPOSITORIES" add $missing || fail "Package installation failed."
fi

[ "$(kernel_version)" = "$rom_kernel" ] || fail "Kernel package changed unexpectedly."
apk info -e tailscale >/dev/null 2>&1 || fail "Tailscale package is missing."
apk info -e kmod-tun >/dev/null 2>&1 || fail "kmod-tun package is missing."
command -v tailscaled >/dev/null 2>&1 || fail "tailscaled is unavailable."
module_present || fail "TUN module is unavailable."
modprobe tun || fail "Kernel rejected the TUN module."
[ -c /dev/net/tun ] || fail "TUN device is unavailable."
[ -x /etc/init.d/tailscale ] || fail "Tailscale service is unavailable."
/etc/init.d/tailscale enable
pidof tailscaled >/dev/null 2>&1 || /etc/init.d/tailscale restart

command -v jsonfilter >/dev/null || fail "jsonfilter is unavailable."
attempt=0
while [ "$attempt" -lt 5 ]; do
  status=$(tailscale status --json 2>/dev/null || true)
  state=$(printf '%s' "$status" | jsonfilter -e '@.BackendState' 2>/dev/null || true)
  online=$(printf '%s' "$status" | jsonfilter -e '@.Self.Online' 2>/dev/null || true)
  [ "$state" = Running ] && [ "$online" = true ] && {
    echo "Tailscale is connected; existing identity and preferences were retained."
    exit 0
  }
  attempt=$((attempt + 1))
  sleep 2
done
fail "Tailscale did not connect; no login or reset was attempted."
