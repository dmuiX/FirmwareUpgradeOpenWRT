#!/bin/sh
set -e

# Configuration for SMB upload - adjust these to your SMB server
SMB_SERVER="//192.168.1.5/openwrt-backup"
SMB_MOUNT="/mnt/openwrt-backup"
SMB_USER="openwrt-backup"
SMB_PASS="h%pJGpJqNn^yx8Kmj@Pi"
SMB_DOMAIN="WORKGROUP"   # Optional, remove if not needed

# Router-specific configuration
TARGET_PATH="targets/mediatek/mt7622"
FIRMWARE_FILE="xiaomi_redmi-router-ax6s-squashfs-sysupgrade.itb"
AUTOMATED_MODE=1  # Set to 1 for fully automated operation

echo "=== OpenWrt Automatic Firmware Upgrade Script ==="

# Check if packages are already installed
NEEDS_PACKAGES=0
if ! opkg list-installed | grep -q openssl-util || \
   ! opkg list-installed | grep -q ca-certificates || \
   ! opkg list-installed | grep -q kmod-fs-cifs || \
   ! opkg list-installed | grep -q libustream-mbedtls; then
  NEEDS_PACKAGES=1
fi

if [ "$NEEDS_PACKAGES" -eq 1 ]; then
  echo "Installing required packages..."
  opkg update || { echo "opkg update failed"; exit 1; }
  
  opkg install openssl-util ca-certificates kmod-fs-cifs libustream-mbedtls || { echo "Package install failed"; exit 1; }
else
  echo "Required packages already installed."
fi

# Detect latest stable release
echo "=== Detecting Latest OpenWrt Release ==="
RELEASES_URL="https://downloads.openwrt.org/releases/"

wget -q -O releases.html "$RELEASES_URL" || { echo "Failed to fetch releases page"; exit 1; }

# Extract version numbers, exclude RC versions, sort and get the latest
LATEST_VERSION=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+/' releases.html | \
                 grep -v 'rc' | \
                 sed 's|/||g' | \
                 sort -V | \
                 tail -n 1)

if [ -z "$LATEST_VERSION" ]; then
  echo "Failed to detect latest version"
  exit 1
fi

echo "Latest stable version detected: $LATEST_VERSION"

# Build download URLs
BASE_URL="https://downloads.openwrt.org/releases/${LATEST_VERSION}/${TARGET_PATH}"
FIRMWARE_URL="${BASE_URL}/openwrt-${LATEST_VERSION}-${FIRMWARE_FILE}"
SHA256_URL="${BASE_URL}/sha256sums"

echo "Firmware URL: $FIRMWARE_URL"

# Download SHA256SUMS file
echo "=== Downloading SHA256 Checksums ==="
wget -q -O sha256sums "$SHA256_URL" || { echo "Failed to download checksums"; exit 1; }

# Extract the checksum for our specific firmware file
EXPECTED_CHECKSUM=$(grep "$FIRMWARE_FILE" sha256sums | awk '{print $1}')

if [ -z "$EXPECTED_CHECKSUM" ]; then
  echo "Failed to find checksum for $FIRMWARE_FILE"
  exit 1
fi

echo "Expected SHA256: $EXPECTED_CHECKSUM"

# Install theme before upgrade
echo "=== Installing LuCI Argon Theme ==="

NEEDS_THEME_UPDATE=0
if ! opkg list-installed | grep -q luci-compat || \
   ! opkg list-installed | grep -q luci-lib-ipkg || \
   ! opkg list-installed | grep -q luci-theme-argon || \
   ! opkg list-installed | grep -q luci-app-argon-config; then
  NEEDS_THEME_UPDATE=1
fi

if [ "$NEEDS_THEME_UPDATE" -eq 1 ]; then
  opkg update || { echo "opkg update failed"; exit 1; }
fi

if ! opkg list-installed | grep -q luci-compat || ! opkg list-installed | grep -q luci-lib-ipkg; then
  opkg install luci-compat luci-lib-ipkg || { echo "Failed to install theme dependencies"; exit 1; }
fi

if ! opkg list-installed | grep -q luci-theme-argon; then
  DEFAULT_THEME_LINK="https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.4.3/luci-theme-argon-2.4.3-r20250722.ipk"
  
  LUCI_ARGON_THEME_FILENAME=$(basename "$DEFAULT_THEME_LINK")
  
  wget -O "$LUCI_ARGON_THEME_FILENAME" "$DEFAULT_THEME_LINK" || { echo "Theme download failed"; exit 1; }
  opkg install "$LUCI_ARGON_THEME_FILENAME" || { echo "Theme install failed"; rm -f "$LUCI_ARGON_THEME_FILENAME"; exit 1; }
  rm -f "$LUCI_ARGON_THEME_FILENAME"
  echo "LuCI Argon theme installed."
else
  echo "LuCI Argon theme already installed."
fi

if ! opkg list-installed | grep -q luci-app-argon-config; then
  DEFAULT_ARGON_CONFIG_LINK="https://github.com/jerrykuku/luci-app-argon-config/releases/download/v0.9/luci-app-argon-config_0.9_all.ipk"
  
  LUCI_APP_ARGON_CONFIG_FILENAME=$(basename "$DEFAULT_ARGON_CONFIG_LINK")

  wget -O "$LUCI_APP_ARGON_CONFIG_FILENAME" "$DEFAULT_ARGON_CONFIG_LINK" || { echo "App download failed"; exit 1; }
  opkg install "$LUCI_APP_ARGON_CONFIG_FILENAME" luci-app-sqm || { echo "App install failed"; rm -f "$LUCI_APP_ARGON_CONFIG_FILENAME"; exit 1; }
  rm -f "$LUCI_APP_ARGON_CONFIG_FILENAME"
  echo "LuCI Argon config app installed."
else
  echo "LuCI Argon config app already installed."
fi

# Set Argon theme as default
CURRENT_THEME=$(uci get luci.main.mediaurlbase 2>/dev/null || echo "")
if [ "$CURRENT_THEME" != "/luci-static/argon" ]; then
  uci set luci.main.mediaurlbase='/luci-static/argon'
  uci commit luci
  /etc/init.d/uhttpd restart || { echo "Warning: uhttpd restart failed"; }
  echo "Argon theme set as default."
else
  echo "Argon theme already set as default."
fi

# Create backup
echo "=== Creating Backup ==="
BACKUPFILE="backup-${HOSTNAME}-$(date +%F).tar.gz"
umask 077
sysupgrade -b "$BACKUPFILE" || { echo "Backup creation failed"; exit 1; }

# Upload backup to SMB
echo "=== Uploading Backup to SMB Share ==="
mkdir -p "$SMB_MOUNT"
mount -t cifs "$SMB_SERVER" "$SMB_MOUNT" -o username="$SMB_USER",password="$SMB_PASS",domain="$SMB_DOMAIN",rw || { echo "Failed to mount SMB share"; exit 1; }

cp "$BACKUPFILE" "$SMB_MOUNT/" || { echo "Failed to copy backup"; umount "$SMB_MOUNT"; exit 1; }

echo "Backup uploaded successfully. Unmounting..."
umount "$SMB_MOUNT"

# Download firmware
echo "=== Downloading Firmware ==="
FIRMWARE_FILENAME="openwrt-${LATEST_VERSION}-${FIRMWARE_FILE}"

wget -O "$FIRMWARE_FILENAME" "$FIRMWARE_URL" || { echo "Firmware download failed"; exit 1; }

# Verify checksum
echo "=== Verifying Firmware Checksum ==="
ACTUAL_CHECKSUM=$(sha256sum "$FIRMWARE_FILENAME" | awk '{print $1}')

if [ "$ACTUAL_CHECKSUM" != "$EXPECTED_CHECKSUM" ]; then
  echo "ERROR: Checksum mismatch!"
  echo "Expected: $EXPECTED_CHECKSUM"
  echo "Got:      $ACTUAL_CHECKSUM"
  exit 1
fi

echo "Checksum verified successfully."

# Test firmware compatibility
echo "=== Testing Firmware Compatibility ==="
if ! sysupgrade -T "$FIRMWARE_FILENAME" 2>&1 | tee error.log; then
  echo "Upgrade test failed:"
  cat error.log
  exit 1
fi

echo "Firmware compatibility test passed."

# Confirm upgrade
if [ "$AUTOMATED_MODE" -eq 0 ]; then
  read -p "Proceed with upgrade to version $LATEST_VERSION? Router will reboot. (y/n): " CONFIRM
  if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Upgrade cancelled by user."
    exit 0
  fi
fi

# Perform upgrade
echo "=== Starting Firmware Upgrade to $LATEST_VERSION ==="
echo "Router will reboot shortly..."

sysupgrade "$FIRMWARE_FILENAME" || { echo "Upgrade failed!"; exit 1; }

