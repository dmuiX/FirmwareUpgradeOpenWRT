#!/bin/sh
set -e

# Configuration for SMB upload - adjust these to your SMB server
SMB_SERVER="//192.168.1.100/backupshare"
SMB_MOUNT="/mnt/backup_smb"
SMB_USER="youruser"
SMB_PASS="yourpassword"
SMB_DOMAIN="WORKGROUP"   # Optional, remove if not needed

echo "Installing required packages..."
opkg update || { echo "opkg update failed"; exit 1; }
opkg install openssl-util ca-certificates cifs-utils || { echo "Package install failed"; exit 1; }

if ! opkg list-installed | grep -q libustream; then
  opkg install libustream-mbedtls || { echo "libustream-mbedtls install failed"; exit 1; }
fi

cd /tmp

echo "Creating backup file..."
BACKUPFILE="backup-${HOSTNAME}-$(date +%F).tar.gz"
umask 077
sysupgrade -b "$BACKUPFILE" || { echo "Backup creation failed"; exit 1; }

echo "Mounting SMB share to upload backup..."
mkdir -p "$SMB_MOUNT"
mount -t cifs "$SMB_SERVER" "$SMB_MOUNT" -o username="$SMB_USER",password="$SMB_PASS",domain="$SMB_DOMAIN",rw || { echo "Failed to mount SMB share"; exit 1; }

echo "Copying backup to SMB share..."
cp "$BACKUPFILE" "$SMB_MOUNT/" || { echo "Failed to copy backup to SMB share"; umount "$SMB_MOUNT"; exit 1; }

echo "Backup uploaded successfully. Unmounting SMB share..."
umount "$SMB_MOUNT"

# Download firmware image
read -p "Enter the firmware download link: " DOWNLOAD_LINK
DOWNLOAD_LINK=${DOWNLOAD_LINK:-https://downloads.openwrt.org/releases/21.02.2/targets/ath79/generic/openwrt-21.02.2-ath79-generic-ubnt_unifiac-lr-squashfs-sysupgrade.bin}

echo "Downloading firmware image..."
wget "$DOWNLOAD_LINK" || { echo "Download failed"; exit 1; }
FILENAME=$(basename "$DOWNLOAD_LINK")

read -p "Enter the SHA256 checksum for verification: " SHA256SUM
if [ -z "$SHA256SUM" ]; then
  echo "No SHA256 checksum provided, aborting."
  exit 1
fi

echo "${SHA256SUM} *${FILENAME}" > sha256sum

echo "Verifying SHA256 checksum..."
if ! sha256sum -c sha256sum; then
  echo "Checksum verification failed, aborting."
  exit 1
fi

echo "Checksum verified."

echo "Testing upgrade image compatibility..."
if ! sysupgrade -T -f "$BACKUPFILE" "$FILENAME" > error.log 2>&1; then
  echo "Upgrade test failed, see error.log:"
  cat error.log
  exit 1
fi

echo "Upgrade test passed. Proceeding with upgrade..."

if ! sysupgrade "$FILENAME"; then
  echo "Upgrade failed!"
  exit 1
fi

echo "Upgrade completed successfully."
