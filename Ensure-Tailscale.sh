#!/bin/sh
# Restore Tailscale after sysupgrade without resetting identity or preferences.
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
for tool in apk uname sed cmp grep; do command -v "$tool" >/dev/null || fail "Required command unavailable: $tool"; done

kernel_version() {
  apk "$@" query --fields version --format yaml --installed kernel | sed -n 's/^- version: //p'
}
release_version() {
  sed -n "s/^DISTRIB_RELEASE='\([^']*\)'$/\1/p" "$1"
}
running_kernel=$(uname -r)
rom_kernel=$(kernel_version --root /rom)
installed_kernel=$(kernel_version)
[ -n "$rom_kernel" ] && [ -n "$installed_kernel" ] || fail "Cannot identify firmware/kernel package metadata."
case "$rom_kernel" in
  "$running_kernel"~*|"$running_kernel"-r*) ;;
  *) fail "Running kernel and firmware image disagree; no packages will be installed." ;;
esac
[ "$installed_kernel" = "$rom_kernel" ] || fail "Kernel package metadata differs from /rom; repair package sources/database first. No force-install attempted."
active_release=$(release_version /etc/openwrt_release) || fail "Cannot read active release metadata."
rom_release=$(release_version /rom/etc/openwrt_release) || fail "Cannot read firmware release metadata."
[ -n "$active_release" ] && [ -n "$rom_release" ] || fail "Release metadata is empty; refusing package changes."
[ "$active_release" = "$rom_release" ] || fail "Restored release metadata differs from /rom; repair the sysupgrade preservation policy first."
cmp -s /etc/apk/repositories.d/distfeeds.list /rom/etc/apk/repositories.d/distfeeds.list || fail "Distribution feeds differ from the running firmware. Refusing automatic package changes."

if [ "$CHECK_ONLY" -eq 1 ]; then
  echo "Firmware, installed kernel metadata and distribution feeds agree. No changes made."
  exit 0
fi

lock=/var/lock/tailscale-auto-install.lock
mkdir "$lock" 2>/dev/null || { echo "Another Tailscale restoration holds the lock; skipping."; exit 0; }
repo_work=
trap '[ -z "$repo_work" ] || rm -rf "$repo_work"; rmdir "$lock"' EXIT
trap 'exit 1' HUP INT TERM

package_attempt() {
  apk --wait 120 "$@" update || return 1
  # Never add a permanent old-kernel constraint to the preserved APK world.
  plan=$(apk --wait 120 "$@" add --simulate tailscale kmod-tun 2>&1) || return 1
  if printf '%s\n' "$plan" | grep -Eq '\) [[:alpha:]]+ kernel[[:space:](]'; then
    echo "ERROR: Package transaction would change the kernel package." >&2
    return 2
  fi
  apk --wait 120 "$@" add tailscale kmod-tun || return 1
}

module_present() {
  # A currently loaded device alone is insufficient: the module file must also
  # survive for the next boot. This bootstrap targets module-based stock images.
  [ -f "/lib/modules/$running_kernel/tun.ko" ] || [ -f "/lib/modules/$running_kernel/tun.ko.gz" ] || [ -f "/lib/modules/$running_kernel/tun.ko.zst" ]
}
if ! apk info -e tailscale >/dev/null 2>&1 || ! command -v tailscaled >/dev/null 2>&1 || ! module_present; then
  # Both bootstraps run near the end of boot. Let Argon's supervised job finish
  # downloading/installing first, and use APK's own lock wait for other clients.
  for tool in ubus jsonfilter; do
    command -v "$tool" >/dev/null || fail "ubus/jsonfilter required to coordinate package jobs."
  done
  argon_wait=0
  while :; do
    busy=$(ubus call service list '{"name":"argon-auto-update"}' 2>/dev/null | jsonfilter -e '@["argon-auto-update"].instances.*.running') || busy=
    case "$busy" in *true*) ;; *) break ;; esac
    [ "$argon_wait" -lt 60 ] || fail "Argon bootstrap is still busy; refusing a concurrent package transaction."
    sleep 2
    argon_wait=$((argon_wait + 1))
  done
  echo "Restoring Tailscale and matching TUN support from signed firmware feeds."
  if package_attempt; then
    :
  else
    rc=$?
    [ "$rc" -ne 2 ] || fail "Kernel change refused; no mirror bypass attempted."
    [ "$(kernel_version)" = "$rom_kernel" ] || fail "Kernel metadata changed; refusing further package operations."
    echo "Primary package source failed; trying HTTPS RWTH mirror with original firmware signing keys."
    repo_work=$(mktemp -d)
    # Change transport host only, never release/architecture/ABI or trust keys.
    if grep -Ev '^[[:space:]]*(#.*)?$|^https://downloads\.openwrt\.org/' /rom/etc/apk/repositories.d/distfeeds.list >/dev/null; then
      fail "Unsupported source URL; no automatic mirror rewrite attempted."
    fi
    sed 's#^https://downloads.openwrt.org/#https://ftp.halifax.rwth-aachen.de/openwrt/#' /rom/etc/apk/repositories.d/distfeeds.list > "$repo_work/mirror.repositories"
    package_attempt --keys-dir /rom/etc/apk/keys --repositories-file "$repo_work/mirror.repositories" || fail "Signed mirror installation failed; no login/reset attempted."
  fi
fi
[ "$(kernel_version)" = "$rom_kernel" ] || fail "Kernel package changed unexpectedly; refusing to start Tailscale."
module_present || fail "No TUN module for the running kernel after installation."
modprobe tun || fail "Kernel rejected the TUN module."
[ -c /dev/net/tun ] || fail "TUN device is still missing."
[ -x /etc/init.d/tailscale ] || fail "Tailscale init service is unavailable."
/etc/init.d/tailscale enable
if ! pidof tailscaled >/dev/null 2>&1; then
  /etc/init.d/tailscale restart
fi
# Preserve the existing login, routes, DNS and other preferences. Never run up,
# login, logout or reset automatically, and never log the complete status JSON.
command -v jsonfilter >/dev/null || fail "jsonfilter is needed for the connection check."
attempt=0
while [ "$attempt" -lt 5 ]; do
  state=$(tailscale status --json 2>/dev/null | jsonfilter -e '@.BackendState') || state=
  online=$(tailscale status --json 2>/dev/null | jsonfilter -e '@.Self.Online') || online=
  if [ "$state" = Running ] && [ "$online" = true ]; then
    echo "Tailscale is running and connected; existing identity/preferences retained."
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 2
done
fail "Tailscale did not become connected. Check its service/state; no automatic login or reset was attempted."
