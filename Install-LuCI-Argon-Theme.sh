#!/bin/sh
# Restore one pinned Argon package after sysupgrade without changing installed packages.
set -eu
umask 077

THEME_VERSION=3.0.0-r2
THEME_FILE="luci-theme-argon-$THEME_VERSION.apk"
THEME_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v3.0.0/$THEME_FILE"
THEME_SHA256=d21fe8574183e4d78b6347431b5e0a4e48666453435b5d07d2ca44de2b491654
THEME_DIR=/www/luci-static/argon

CHECK_ONLY=0
case "${1:-}" in
  --check) CHECK_ONLY=1 ;;
  --non-interactive|'') ;;
  *) echo "Usage: $0 [--check|--non-interactive]" >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || exit 2

fail() { echo "ERROR: $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || fail "Run as root."
for tool in apk cmp grep sed sha256sum uname uci wget; do command -v "$tool" >/dev/null || fail "Required command unavailable: $tool"; done

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
cmp -s /etc/apk/repositories.d/distfeeds.list /rom/etc/apk/repositories.d/distfeeds.list || fail "Distribution feeds differ from /rom."

[ "$CHECK_ONLY" -eq 0 ] || { echo "Firmware metadata is coherent. No changes made."; exit 0; }

lock=/var/lock/post-sysupgrade-package-install.lock
attempt=0
while ! mkdir "$lock" 2>/dev/null; do
  [ "$attempt" -lt 60 ] || fail "Package restoration lock remained busy."
  attempt=$((attempt + 1))
  sleep 2
done
work=
trap '[ -z "$work" ] || rm -rf "$work"; rmdir "$lock"' EXIT
trap 'exit 1' HUP INT TERM

activate_theme() {
  [ -d "$THEME_DIR" ] || fail "Argon is installed but its files are missing."
  if [ "$(uci get luci.main.mediaurlbase 2>/dev/null || true)" != /luci-static/argon ]; then
    uci set luci.main.mediaurlbase=/luci-static/argon
    uci commit luci
    /etc/init.d/uhttpd restart
  fi
  echo "LuCI Argon is installed and active."
}

if apk info -e luci-theme-argon >/dev/null 2>&1; then
  activate_theme
  exit 0
fi
# Sysupgrade may restore unowned theme files from the previous overlay. They do
# not represent an installed package and may be replaced by the pinned package.
work=$(mktemp -d /tmp/argon-restore.XXXXXX) || fail "Cannot create download directory."
package=$work/$THEME_FILE
download_attempt=1
while ! wget -T 30 -O "$package" "$THEME_URL"; do
  [ "$download_attempt" -lt 3 ] || fail "Argon download failed."
  download_attempt=$((download_attempt + 1))
done
printf '%s  %s\n' "$THEME_SHA256" "$package" | sha256sum -c - >/dev/null || fail "Argon checksum mismatch."

plan=$(apk --wait 120 --repositories-file /dev/null add --allow-untrusted --simulate "$package" 2>&1) || fail "Cannot calculate Argon package plan."
changes=$(printf '%s\n' "$plan" | grep -E '^\([[:space:]]*[0-9]+/[0-9]+\) ' || true)
[ "$(printf '%s\n' "$changes" | grep -Ec '^\([[:space:]]*[0-9]+/[0-9]+\) Installing luci-theme-argon \(3\.0\.0-r2\)$' || true)" -eq 1 ] || fail "Argon plan is not the pinned theme installation."
[ "$(printf '%s\n' "$changes" | grep -c . || true)" -eq 1 ] || fail "Argon plan contains additional package changes."
apk --wait 120 --repositories-file /dev/null add --allow-untrusted "$package" || fail "Argon installation failed."

apk info -e luci-theme-argon >/dev/null 2>&1 || fail "Argon package is still missing."
activate_theme
