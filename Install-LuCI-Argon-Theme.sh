#!/bin/sh
set -e

cd /tmp

# Check if a package is installed (apk-based OpenWRT 25.10+)
pkg_installed() {
  apk info -e "$1" 2>/dev/null
}

# Install a local .ipk file.
# apk cannot install .ipk directly, so we use opkg if available,
# otherwise fall back to manual tar extraction.
install_ipk() {
  local pkg_file="$1"
  if command -v opkg >/dev/null 2>&1; then
    opkg install --allow-untrusted "$pkg_file" || { echo "opkg install failed: $pkg_file"; return 1; }
  else
    echo "opkg not found, extracting $pkg_file manually..."
    local tmp_dir
    tmp_dir=$(mktemp -d)
    tar -xzf "$pkg_file" -C "$tmp_dir" || { echo "Failed to unpack $pkg_file"; rm -rf "$tmp_dir"; return 1; }
    if [ -f "$tmp_dir/data.tar.gz" ]; then
      tar -xzf "$tmp_dir/data.tar.gz" -C / || { echo "data.tar.gz extraction failed"; rm -rf "$tmp_dir"; return 1; }
    elif [ -f "$tmp_dir/data.tar.xz" ]; then
      tar -xJf "$tmp_dir/data.tar.xz" -C / || { echo "data.tar.xz extraction failed"; rm -rf "$tmp_dir"; return 1; }
    else
      echo "No data archive found in $pkg_file"; rm -rf "$tmp_dir"; return 1
    fi
    rm -rf "$tmp_dir"
  fi
}


# Install Argon theme (.ipk from GitHub)
if ! pkg_installed luci-theme-argon; then
  DEFAULT_THEME_LINK="https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.4.3/luci-theme-argon-2.4.3-r20250722.apk"

  read -p "Argon theme download link [${DEFAULT_THEME_LINK}]: " LUCI_ARGON_THEME_LINK
  LUCI_ARGON_THEME_LINK=${LUCI_ARGON_THEME_LINK:-$DEFAULT_THEME_LINK}
  LUCI_ARGON_THEME_FILENAME=$(basename "$LUCI_ARGON_THEME_LINK")

  wget -O "$LUCI_ARGON_THEME_FILENAME" "$LUCI_ARGON_THEME_LINK" || { echo "Theme download failed"; exit 1; }
  case "$LUCI_ARGON_THEME_FILENAME" in
    *.apk) apk add --allow-untrusted --no-deps "./$LUCI_ARGON_THEME_FILENAME" || { echo "Theme install failed"; rm -f "$LUCI_ARGON_THEME_FILENAME"; exit 1; } ;;
    *.ipk) install_ipk "$LUCI_ARGON_THEME_FILENAME" || { rm -f "$LUCI_ARGON_THEME_FILENAME"; exit 1; } ;;
    *) echo "Unknown package format: $LUCI_ARGON_THEME_FILENAME"; rm -f "$LUCI_ARGON_THEME_FILENAME"; exit 1 ;;
  esac
  rm -f "$LUCI_ARGON_THEME_FILENAME"
  echo "LuCI Argon theme installed."
else
  echo "LuCI Argon theme already installed."
fi

# Persistently set Argon as active theme
CURRENT_THEME=$(uci get luci.main.mediaurlbase 2>/dev/null || echo "")
if [ "$CURRENT_THEME" != "/luci-static/argon" ]; then
  uci set luci.main.mediaurlbase='/luci-static/argon'
  uci commit luci
  /etc/init.d/uhttpd restart || echo "Warning: uhttpd restart failed"
  echo "Argon theme activated and uhttpd restarted."
else
  echo "Argon theme already active."
fi

echo "Theme setup completed successfully."
