#!/bin/sh
set -eu

SCRIPT_DIR=$(unset CDPATH; cd "$(dirname "$0")" && pwd)
SOURCE="$SCRIPT_DIR/Tailscale-Auto-Install.init"
INSTALLER="$SCRIPT_DIR/Ensure-Tailscale.sh"
TARGET=/etc/init.d/tailscale-auto-install
SYSUPGRADE_CONF=/etc/sysupgrade.conf

[ "$(id -u)" -eq 0 ] || { echo "Run as root." >&2; exit 1; }
[ "$SCRIPT_DIR" = /root/FirmwareUpgradeOpenWRT ] || {
  echo "Install this repository at /root/FirmwareUpgradeOpenWRT first." >&2
  exit 1
}
[ -f "$SOURCE" ] && [ -x "$INSTALLER" ] || {
  echo "Service definition or executable installer is missing." >&2
  exit 1
}
[ -f "$SYSUPGRADE_CONF" ] && [ ! -L "$SYSUPGRADE_CONF" ] || {
  echo "Expected a regular /etc/sysupgrade.conf; refusing to replace it." >&2
  exit 1
}

preserve() {
  grep -Fqx "$1" "$SYSUPGRADE_CONF" || printf '%s\n' "$1" >> "$SYSUPGRADE_CONF"
}
# Do not persist/enable an installer against an already inconsistent firmware.
"$INSTALLER" --check
cp "$SOURCE" "$TARGET"
chmod 755 "$TARGET"
"$TARGET" enable
preserve /root/FirmwareUpgradeOpenWRT
preserve /etc/init.d/tailscale-auto-install
preserve /etc/rc.d/S99tailscale-auto-install
preserve /etc/config/tailscale
preserve /etc/tailscale
"$TARGET" start
printf '%s\n' 'Automatic Tailscale restoration enabled; this does not confirm a successful package install or connection.'
printf '%s\n' 'Inspect: logread -e Ensure-Tailscale'
