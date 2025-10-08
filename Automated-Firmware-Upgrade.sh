#!/bin/sh
set -e

cd /tmp

# Load environment variables from .env file
ENV_FILE="/root/FirmwareUpgradeOpenWRT/.env"

if [ -f "$ENV_FILE" ]; then
  # Source the .env file
  . "$ENV_FILE"
  echo "Loaded configuration from $ENV_FILE"
else
  echo "ERROR: Configuration file not found: $ENV_FILE"
  echo ""
  echo "Create the file with:"
  echo ""
  cat << 'ENVEXAMPLE'
cat > /root/FirmwareUpgradeOpenWRT/.env << 'EOF'
# SMB Backup Configuration
SMB_SERVER=//192.168.1.5/openwrt-backups
SMB_MOUNT=/mnt/openwrt-backups
SMB_USER=openwrt-backup
SMB_PASSWORD=your-password-here
SMB_DOMAIN=WORKGROUP

# Router Configuration
TARGET=mediatek
SUBTARGET=mt7622
DEVICE_NAME=xiaomi_redmi-router-ax6s

# Upgrade Settings
FACTORY_UPGRADE=0  # Set to 1 for factory upgrade (wipes config)
AUTOMATED_MODE=0   # Set to 1 for fully automated operation (no prompts)
EOF
ENVEXAMPLE
  echo ""
  echo "Then secure it with:"
  echo "  chmod 600 /root/FirmwareUpgradeOpenWRT/.env"
  echo ""
  exit 1
fi

# Validate required variables
REQUIRED_VARS="SMB_SERVER SMB_MOUNT SMB_USER SMB_PASSWORD TARGET SUBTARGET DEVICE_NAME"
for VAR in $REQUIRED_VARS; do
  eval VALUE=\$$VAR
  if [ -z "$VALUE" ]; then
    echo "ERROR: Required variable $VAR is not set in $ENV_FILE"
    exit 1
  fi
done

# Set defaults for optional variables
SMB_DOMAIN="${SMB_DOMAIN:-WORKGROUP}"
FACTORY_UPGRADE="${FACTORY_UPGRADE:-0}"
AUTOMATED_MODE="${AUTOMATED_MODE:-0}"

echo "=== OpenWrt Automatic Firmware Upgrade Script ==="

# Set firmware type and extension based on upgrade mode
if [ "$FACTORY_UPGRADE" -eq 1 ]; then
  FIRMWARE_TYPE="factory"
  FIRMWARE_EXT="bin"
  echo "Mode: FACTORY UPGRADE (will wipe configuration)"
else
  FIRMWARE_TYPE="squashfs-sysupgrade"
  FIRMWARE_EXT="itb"
  echo "Mode: STANDARD UPGRADE (will keep configuration)"
fi

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
BASE_URL="https://downloads.openwrt.org/releases/${LATEST_VERSION}/targets/${TARGET}/${SUBTARGET}"
FIRMWARE_FILENAME="openwrt-${LATEST_VERSION}-${TARGET}-${SUBTARGET}-${DEVICE_NAME}-${FIRMWARE_TYPE}.${FIRMWARE_EXT}"
FIRMWARE_URL="${BASE_URL}/${FIRMWARE_FILENAME}"
SHA256_URL="${BASE_URL}/sha256sums"

echo "Firmware URL: $FIRMWARE_URL"

# Create backup
echo "=== Creating Backup ==="
BACKUPFILE="backup-${HOSTNAME}-$(date +%F).tar.gz"
umask 077
sysupgrade -b "$BACKUPFILE" || { echo "Backup creation failed"; exit 1; }
echo "Backup created: $BACKUPFILE"

# Upload backup to SMB
echo "=== Uploading Backup to SMB Share ==="
mkdir -p "$SMB_MOUNT"
mount -t cifs "$SMB_SERVER" "$SMB_MOUNT" -o username="$SMB_USER",password="$SMB_PASSWORD",domain="$SMB_DOMAIN",rw || { echo "Failed to mount SMB share"; exit 1; }

cp "$BACKUPFILE" "$SMB_MOUNT/" || { echo "Failed to copy backup"; umount "$SMB_MOUNT"; exit 1; }

echo "Backup uploaded successfully. Unmounting..."
umount "$SMB_MOUNT"

# Download SHA256SUMS file
echo "=== Downloading SHA256 Checksums ==="
wget -q -O sha256sums "$SHA256_URL" || { echo "Failed to download checksums"; exit 1; }

# Extract the checksum for our specific firmware file
EXPECTED_CHECKSUM=$(grep "${DEVICE_NAME}-${FIRMWARE_TYPE}.${FIRMWARE_EXT}" sha256sums | awk '{print $1}')

if [ -z "$EXPECTED_CHECKSUM" ]; then
  echo "Failed to find checksum for firmware file"
  echo "Looking for: ${DEVICE_NAME}-${FIRMWARE_TYPE}.${FIRMWARE_EXT}"
  exit 1
fi

echo "Expected SHA256: $EXPECTED_CHECKSUM"

# Download firmware
echo "=== Downloading Firmware ==="
echo "Firmware filename: $FIRMWARE_FILENAME"
echo "Downloading from: $FIRMWARE_URL"
echo ""

wget -O "$FIRMWARE_FILENAME" "$FIRMWARE_URL" || { echo "Firmware download failed"; exit 1; }

# Verify the file was downloaded
if [ ! -f "$FIRMWARE_FILENAME" ]; then
  echo "ERROR: Firmware file not found after download!"
  echo "Expected: $FIRMWARE_FILENAME"
  exit 1
fi

echo "Firmware downloaded successfully: $(ls -lh $FIRMWARE_FILENAME)"

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

# Test firmware compatibility (skip for factory images as they're not meant for sysupgrade -T)
if [ "$FACTORY_UPGRADE" -eq 0 ]; then
  echo "=== Testing Firmware Compatibility ==="
  sysupgrade -T "$FIRMWARE_FILENAME" 2>&1
  SYSUPGRADE_EXIT=$?

  if [ $SYSUPGRADE_EXIT -ne 0 ]; then
    echo ""
    echo "WARNING: Firmware compatibility test failed!"
    echo "This upgrade may require factory image."
    echo "Set FACTORY_UPGRADE=1 in .env to use factory image instead."
    exit 1
  fi
  echo "Firmware compatibility test passed."
else
  echo "=== Skipping Compatibility Test (factory image) ==="
fi

# Confirm upgrade
if [ "$AUTOMATED_MODE" -eq 0 ]; then
  echo ""
  if [ "$FACTORY_UPGRADE" -eq 1 ]; then
    read -p "Proceed with FACTORY upgrade to $LATEST_VERSION? This will WIPE configuration! (y/n): " CONFIRM
  else
    read -p "Proceed with upgrade to $LATEST_VERSION? Router will reboot. (y/n): " CONFIRM
  fi
  
  if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Upgrade cancelled by user."
    exit 0
  fi
fi

# Perform upgrade
echo "=== Starting Firmware Upgrade to $LATEST_VERSION ==="

if [ "$FACTORY_UPGRADE" -eq 1 ]; then
  echo "Using factory image with config wipe..."
  echo "Router will reboot shortly..."
  sysupgrade -F -n "$FIRMWARE_FILENAME" || { echo "Upgrade failed!"; exit 1; }
else
  echo "Using sysupgrade image (keeping configuration)..."
  echo "Router will reboot shortly..."
  sysupgrade "$FIRMWARE_FILENAME" || { echo "Upgrade failed!"; exit 1; }
fi

