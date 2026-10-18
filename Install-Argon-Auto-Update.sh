#!/bin/sh
set -e

SCRIPT_DIR=$(unset CDPATH; cd "$(dirname "$0")" && pwd)
SOURCE="$SCRIPT_DIR/Argon-Auto-Update.init"
TARGET=/etc/init.d/argon-auto-update
INSTALLER="$SCRIPT_DIR/Install-LuCI-Argon-Theme.sh"
SYSUPGRADE_CONF=/etc/sysupgrade.conf

preserve_across_sysupgrade() {
  path=$1
  grep -Fqx "$path" "$SYSUPGRADE_CONF" 2>/dev/null || printf '%s\n' "$path" >>"$SYSUPGRADE_CONF"
}

[ "$(id -u)" -eq 0 ] || {
  echo "This setup must run as root" >&2
  exit 1
}
[ -f "$SOURCE" ] || {
  echo "Missing service definition: $SOURCE" >&2
  exit 1
}
[ -x "$INSTALLER" ] || {
  echo "Installer not found or not executable: $INSTALLER" >&2
  exit 1
}
[ "$INSTALLER" = "/root/FirmwareUpgradeOpenWRT/Install-LuCI-Argon-Theme.sh" ] || {
  echo "Clone the repository at /root/FirmwareUpgradeOpenWRT before enabling automatic updates" >&2
  exit 1
}

cp "$SOURCE" "$TARGET"
chmod 755 "$TARGET"
"$TARGET" enable

preserve_across_sysupgrade /root/FirmwareUpgradeOpenWRT
preserve_across_sysupgrade /etc/init.d/argon-auto-update
preserve_across_sysupgrade /etc/rc.d/S99argon-auto-update

"$TARGET" restart

echo "Argon automatic updates enabled. Check its output with: logread -e Install-LuCI-Argon-Theme.sh"
