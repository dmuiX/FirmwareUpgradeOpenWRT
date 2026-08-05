#!/bin/sh
set -e

cd /tmp

DEFAULT_THEME_LINK="https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.4.6/luci-theme-argon-2.4.6-r1.apk"
DEFAULT_ARGON_CONFIG_LINK="https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.4.6/luci-app-argon-config-2.4.6-r1.apk"

read -r -p "Argon theme download link [${DEFAULT_THEME_LINK}]: " LINK
LINK=${LINK:-$DEFAULT_THEME_LINK}
FILE=$(basename "$LINK")

read -r -p "Argon config download link [${DEFAULT_ARGON_CONFIG_LINK}]: " CONFIG_LINK
CONFIG_LINK=${CONFIG_LINK:-$DEFAULT_ARGON_CONFIG_LINK}
CONFIG_FILE=$(basename "$CONFIG_LINK")

echo "Downloading Argon theme..."
wget -O "$FILE" "$LINK" || { echo "Theme download failed"; exit 1; }

echo "Downloading Argon config app..."
wget -O "$CONFIG_FILE" "$CONFIG_LINK" || { echo "Config app download failed"; exit 1; }

# The theme package depends on luci-app-argon-config.  Both local APKs must
# therefore be supplied in the same apk transaction.
if ! apk add --allow-untrusted "./$FILE" "./$CONFIG_FILE"; then
  echo "Install failed"
  exit 1
fi
rm -f "$FILE" "$CONFIG_FILE"

if ! apk info -e luci-theme-argon >/dev/null 2>&1 || \
   ! apk info -e luci-app-argon-config >/dev/null 2>&1; then
  echo "Install failed: one or more Argon packages are missing"
  exit 1
fi
echo "LuCI Argon theme and config app installed."

# Set Argon as active theme
if [ "$(uci get luci.main.mediaurlbase 2>/dev/null)" != "/luci-static/argon" ]; then
  uci set luci.main.mediaurlbase='/luci-static/argon'
  uci commit luci
  /etc/init.d/uhttpd restart || echo "Warning: uhttpd restart failed"
  echo "Argon theme activated and uhttpd restarted."
else
  echo "Argon theme already active."
fi
