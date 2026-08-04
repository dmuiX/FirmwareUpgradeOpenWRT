#!/bin/sh
set -e

cd /tmp

DEFAULT_THEME_LINK="https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.4.6/luci-theme-argon-2.4.6-r1.apk"
DEFAULT_ARGON_CONFIG_LINK="https://github.com/jerrykuku/luci-app-argon/releases/download/v2.4.6/luci-app-argon-config-2.4.6-r1.apk"

# Skip if already installed
#if apk info -e luci-theme-argon 2>/dev/null; then # must ask for version
#  echo "LuCI Argon theme already installed."
#else
read -p "Argon theme download link [${DEFAULT_THEME_LINK}]"
LINK=${LINK:-$DEFAULT_THEME_LINK}
FILE=$(basename "$LINK")

wget -O "$FILE" "$LINK" || { echo "Download failed"; exit 1; }
apk add --allow-untrusted "./$FILE" || true
rm -f "$FILE"
if ! apk info -e luci-theme-argon 2>/dev/null; then
  echo "Install failed"; exit 1
fi
echo "LuCI Argon theme installed."
#fi

# Install Argon Theme Config App
#if apk info -e luci-app-argon-config; 2>/dev/null; then #same version is missing
#  echo "LuCI Argon config already installed."
#else
read -p "Argon config download link [$DEFAULT_ARGON_CONFIG_LINK]"
CONFIG_LINK=${CONFIG_LINK:-$DEFAULT_ARGON_CONFIG_LINK}
CONFIG_FILE=$(basename "$CONFIG_LINK")

wget -O "$CONFIG_FILE" "$CONFIG_LINK" || { echo "Download failed"; exit 1; }
apk add --allow-untrusted "./$CONFIG_FILE" || true
rm -f "$CONFIG_FILE"
if ! apk info -e luci-app-argon-config 2>/dev/null; then
  echo "Install failed"; exit 1
fi
echo "LuCI Argon config app installed."
#fi

# Set Argon as active theme
if [ "$(uci get luci.main.mediaurlbase 2>/dev/null)" != "/luci-static/argon" ]; then
  uci set luci.main.mediaurlbase='/luci-static/argon'
  uci commit luci
  /etc/init.d/uhttpd restart || echo "Warning: uhttpd restart failed"
  echo "Argon theme activated and uhttpd restarted."
else
  echo "Argon theme already active."
fi
