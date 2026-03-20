#!/bin/sh
set -e

cd /tmp

DEFAULT_THEME_LINK="https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.4.3/luci-theme-argon-2.4.3-r20250722.apk"

# Skip if already installed
if apk info -e luci-theme-argon 2>/dev/null; then
  echo "LuCI Argon theme already installed."
else
  read -p "Argon theme download link [${DEFAULT_THEME_LINK}]: " LINK
  LINK=${LINK:-$DEFAULT_THEME_LINK}
  FILE=$(basename "$LINK")

  wget -O "$FILE" "$LINK" || { echo "Download failed"; exit 1; }
  apk add --allow-untrusted "./$FILE" || { echo "Install failed"; rm -f "$FILE"; exit 1; }
  rm -f "$FILE"
  echo "LuCI Argon theme installed."
fi

# Set Argon as active theme
if [ "$(uci get luci.main.mediaurlbase 2>/dev/null)" != "/luci-static/argon" ]; then
  uci set luci.main.mediaurlbase='/luci-static/argon'
  uci commit luci
  /etc/init.d/uhttpd restart || echo "Warning: uhttpd restart failed"
  echo "Argon theme activated and uhttpd restarted."
else
  echo "Argon theme already active."
fi
