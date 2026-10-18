#!/bin/sh
set -e

cd /tmp

# Argon 3 includes its configuration UI in the theme package. The similarly
# named luci-app-argon-config package is only needed once to migrate old installs.
DEFAULT_THEME_LINK="https://github.com/jerrykuku/luci-theme-argon/releases/download/v3.0.0/luci-theme-argon-3.0.0-r2.apk"
DEFAULT_ARGON_CONFIG_LINK="https://github.com/jerrykuku/luci-theme-argon/releases/download/v3.0.0/luci-app-argon-config-3.0.0-r2.apk"
THEME_FILE=
CONFIG_FILE=

cleanup() {
  [ -z "$THEME_FILE" ] || rm -f "$THEME_FILE"
  [ -z "$CONFIG_FILE" ] || rm -f "$CONFIG_FILE"
}
trap cleanup EXIT

if apk info -e luci-app-argon-config >/dev/null 2>&1; then
  echo "Existing Argon configuration detected; installing the Argon 3 migration package first."
  printf "Argon config migration download link [%s]: " "$DEFAULT_ARGON_CONFIG_LINK"
  read -r CONFIG_LINK
  CONFIG_LINK=${CONFIG_LINK:-$DEFAULT_ARGON_CONFIG_LINK}
  CONFIG_FILE=$(basename "$CONFIG_LINK")

  wget -O "$CONFIG_FILE" "$CONFIG_LINK" || { echo "Download failed"; exit 1; }
  apk add --allow-untrusted "./$CONFIG_FILE" || { echo "Migration failed"; exit 1; }
  echo "Argon configuration migrated."
elif grep -q '^luci-app-argon-config' /etc/apk/world 2>/dev/null; then
  # A firmware backup can restore a world entry without restoring the package.
  # Remove only that stale request; there is no installed package to migrate.
  echo "Removing stale luci-app-argon-config entry from /etc/apk/world."
  sed -i '/^luci-app-argon-config/d' /etc/apk/world
fi

printf "Argon theme download link [%s]: " "$DEFAULT_THEME_LINK"
read -r THEME_LINK
THEME_LINK=${THEME_LINK:-$DEFAULT_THEME_LINK}
THEME_FILE=$(basename "$THEME_LINK")

wget -O "$THEME_FILE" "$THEME_LINK" || { echo "Download failed"; exit 1; }
apk add --allow-untrusted "./$THEME_FILE" || { echo "Install failed"; exit 1; }

if ! apk info -e luci-theme-argon >/dev/null 2>&1; then
  echo "Install failed: luci-theme-argon is not installed"
  exit 1
fi
echo "LuCI Argon theme and integrated configuration UI installed."

# Set Argon as active theme
if [ "$(uci get luci.main.mediaurlbase 2>/dev/null)" != "/luci-static/argon" ]; then
  uci set luci.main.mediaurlbase='/luci-static/argon'
  uci commit luci
  /etc/init.d/uhttpd restart || echo "Warning: uhttpd restart failed"
  echo "Argon theme activated and uhttpd restarted."
else
  echo "Argon theme already active."
fi
