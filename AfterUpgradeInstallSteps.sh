#!/bin/sh
set -e

cd /tmp

# Check if any work is needed before updating opkg
NEEDS_UPDATE=0
if ! opkg list-installed | grep -q luci-compat || ! opkg list-installed | grep -q luci-lib-ipkg || \
   ! opkg list-installed | grep -q luci-theme-argon || ! opkg list-installed | grep -q luci-app-argon-config; then
  NEEDS_UPDATE=1
fi

if [ "$NEEDS_UPDATE" -eq 1 ]; then
  echo "Updating package list..."
  opkg update || { echo "opkg update failed"; exit 1; }
fi

# Install dependencies if missing
if ! opkg list-installed | grep -q luci-compat || ! opkg list-installed | grep -q luci-lib-ipkg; then
  opkg install luci-compat luci-lib-ipkg || { echo "Failed to install dependencies"; exit 1; }
fi

if ! opkg list-installed | grep -q luci-theme-argon; then
  DEFAULT_THEME_LINK="https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.4.3/luci-theme-argon-2.4.3-r20250722.ipk"
  
  read -p "Enter current LuCI Argon theme download link. Defaults to [${DEFAULT_THEME_LINK}]: " LUCI_ARGON_THEME_LINK
  LUCI_ARGON_THEME_LINK=${LUCI_ARGON_THEME_LINK:-$DEFAULT_THEME_LINK}
  LUCI_ARGON_THEME_FILENAME=$(basename "$LUCI_ARGON_THEME_LINK")
  
  wget -O "$LUCI_ARGON_THEME_FILENAME" "$LUCI_ARGON_THEME_LINK" || { echo "Theme download failed"; exit 1; }
  opkg install "$LUCI_ARGON_THEME_FILENAME" || { echo "Theme install failed"; rm -f "$LUCI_ARGON_THEME_FILENAME"; exit 1; }
  rm -f "$LUCI_ARGON_THEME_FILENAME"

  echo "LuCI Argon theme installed."
else
  echo "LuCI Argon theme already installed."
fi

if ! opkg list-installed | grep -q luci-app-argon-config; then
  DEFAULT_ARGON_CONFIG_LINK="https://github.com/jerrykuku/luci-app-argon-config/releases/download/v0.9/luci-app-argon-config_0.9_all.ipk"
  
  read -p "Enter current LuCI Argon config app download link. Defaults to [${DEFAULT_ARGON_CONFIG_LINK}]: " LUCI_APP_ARGON_CONFIG_LINK
  LUCI_APP_ARGON_CONFIG_LINK=${LUCI_APP_ARGON_CONFIG_LINK:-$DEFAULT_ARGON_CONFIG_LINK}
  LUCI_APP_ARGON_CONFIG_FILENAME=$(basename "$LUCI_APP_ARGON_CONFIG_LINK")

  wget -O "$LUCI_APP_ARGON_CONFIG_FILENAME" "$LUCI_APP_ARGON_CONFIG_LINK" || { echo "App download failed"; exit 1; }
  opkg install "$LUCI_APP_ARGON_CONFIG_FILENAME" luci-app-sqm || { echo "App install failed"; rm -f "$LUCI_APP_ARGON_CONFIG_FILENAME"; exit 1; }
  rm -f "$LUCI_APP_ARGON_CONFIG_FILENAME"

  echo "LuCI Argon config app installed."
else
  echo "LuCI Argon config app already installed."
fi

# Persistently set Argon theme
CURRENT_THEME=$(uci get luci.main.mediaurlbase 2>/dev/null || echo "")
if [ "$CURRENT_THEME" != "/luci-static/argon" ]; then
  uci set luci.main.mediaurlbase='/luci-static/argon'
  uci commit luci
  /etc/init.d/uhttpd restart || { echo "Warning: uhttpd restart failed"; }
  echo "Argon theme set and web server restarted."
else
  echo "Argon theme already set."
fi

echo "Theme setup completed successfully."
