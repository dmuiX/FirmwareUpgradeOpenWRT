#!/bin/sh
set -eE
cd /tmp

# Error handling
trap 'echo "ERROR at line $LINENO. Backup: $BACKUP"; exit 1' ERR
trap 'rm -f releases.html sha256sums 2>/dev/null' EXIT

# Load config
ENV_FILE="/root/FirmwareUpgradeOpenWRT/.env"
[ -f "$ENV_FILE" ] || { echo "ERROR: $ENV_FILE not found"; exit 1; }
. "$ENV_FILE"

# Validate vars
for V in SMB_SERVER SMB_MOUNT SMB_USER SMB_PASSWORD TARGET SUBTARGET DEVICE_NAME; do
  eval [ -z "\$$V" ] && { echo "ERROR: $V not set"; exit 1; }
done

FACTORY_UPGRADE="${FACTORY_UPGRADE:-0}"; AUTOMATED_MODE="${AUTOMATED_MODE:-0}"

echo "=== OpenWrt Safe Upgrade ==="
echo "Device: $DEVICE_NAME ($TARGET/$SUBTARGET)"

# Set firmware type
if [ "$FACTORY_UPGRADE" -eq 1 ]; then
  TYPE="factory"; EXT="bin"; echo "Mode: FACTORY (wipes config)"
else
  TYPE="squashfs-sysupgrade"; EXT="itb"; echo "Mode: SYSUPGRADE (keeps config)"
fi

# Safe download function
dl() {
  wget --spider "$1" 2>&1 | grep -q "200 OK" || { echo "ERROR: 404 - $1"; return 1; }
  wget --tries=3 --waitretry=5 --timeout=30 -c ${3:+--progress=dot:giga} -O "$2" "$1" || return 1
  [ $(stat -c%s "$2") -lt 1024 ] && { echo "ERROR: File too small"; rm -f "$2"; return 1; }
}

# Check space
[ $(df /tmp | awk 'NR==2 {print $4}') -lt 10240 ] && { echo "ERROR: Low space in /tmp"; exit 1; }

# Install packages if needed
opkg list-installed | grep -q "kmod-fs-cifs" || {
  echo "Installing packages..."; opkg update && opkg install openssl-util ca-certificates kmod-fs-cifs libustream-mbedtls || exit 1
}

# Detect version
dl "https://downloads.openwrt.org/releases/" "releases.html" || exit 1
VER=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+/' releases.html | grep -v rc | sed 's|/||g' | sort -V | tail -1)
[ -z "$VER" ] && { echo "ERROR: Cannot detect version"; exit 1; }

CUR=$(cat /etc/openwrt_release | grep DISTRIB_RELEASE | cut -d= -f2 | tr -d "'")
echo "Current: $CUR → Target: $VER"
[ "$CUR" = "$VER" ] && { echo "Already latest version"; exit 0; }

# Build URLs
BASE="https://downloads.openwrt.org/releases/${VER}/targets/${TARGET}/${SUBTARGET}"
FW="openwrt-${VER}-${TARGET}-${SUBTARGET}-${DEVICE_NAME}-${TYPE}.${EXT}"

# Backup
echo "Creating backup..."
BAK="backup-${HOSTNAME}-$(date +%F-%H%M%S).tar.gz"
sysupgrade -b "$BAK" || { echo "ERROR: Backup failed"; exit 1; }
[ $(stat -c%s "$BAK") -lt 1024 ] && { echo "ERROR: Backup too small"; exit 1; }
tar -tzf "$BAK" >/dev/null 2>&1 || { echo "ERROR: Backup corrupted"; exit 1; }
echo "✓ Backup: $BAK"
BACKUP="$BAK"  # For error trap

# Upload to SMB
echo "Uploading backup..."
SRV=$(echo "$SMB_SERVER" | sed 's|//||' | cut -d/ -f1)
if ping -c1 -W2 "$SRV" >/dev/null 2>&1 && mkdir -p "$SMB_MOUNT" && \
   mount -t cifs "$SMB_SERVER" "$SMB_MOUNT" -o username="$SMB_USER",password="$SMB_PASSWORD",domain="${SMB_DOMAIN:-WORKGROUP}",rw,timeout=15 2>/dev/null; then
  cp "$BAK" "$SMB_MOUNT/" && echo "✓ Uploaded to SMB" || echo "WARNING: Upload failed"
  umount "$SMB_MOUNT"
else
  echo "WARNING: SMB unavailable, backup is local only"
fi

# Download checksums
dl "${BASE}/sha256sums" "sha256sums" || { echo "ERROR: Cannot get checksums"; exit 1; }
[ -s sha256sums ] || { echo "ERROR: Checksums empty"; exit 1; }

# Extract checksum
CHK=$(grep "${DEVICE_NAME}-${TYPE}\.${EXT}" sha256sums | awk '{print $1}')
if [ -z "$CHK" ]; then
  echo "ERROR: Checksum not found for ${DEVICE_NAME}-${TYPE}.${EXT}"
  echo "Available:"; grep "$DEVICE_NAME" sha256sums | awk '{print "  "$2}' || echo "  None"
  exit 1
fi
[ ${#CHK} -ne 64 ] && { echo "ERROR: Invalid checksum format"; exit 1; }

# Download firmware
echo "Downloading firmware..."
dl "${BASE}/${FW}" "$FW" "progress" || { echo "ERROR: Download failed"; exit 1; }

# Verify size
SZ=$(stat -c%s "$FW")
[ "$SZ" -lt 5000000 ] && { echo "ERROR: Firmware too small ($SZ bytes)"; rm -f "$FW"; exit 1; }
echo "✓ Size: $((SZ/1024/1024))MB"

# Check file type
FT=$(file -b "$FW" 2>/dev/null || echo "unknown")
echo "$FT" | grep -qiE "html|ascii text" && { echo "ERROR: Downloaded HTML/text not firmware!"; rm -f "$FW"; exit 1; }

# Verify checksum
echo "Verifying checksum..."
ACT=$(sha256sum "$FW" | awk '{print $1}')
if [ "$ACT" != "$CHK" ]; then
  echo "CRITICAL: CHECKSUM MISMATCH!"
  echo "Expected: $CHK"; echo "Got: $ACT"
  rm -f "$FW"; exit 1
fi
echo "✓ Checksum OK"

# Test firmware
echo "Testing firmware..."
if ! sysupgrade -T "$FW" >/dev/null 2>&1; then
  echo "WARNING: Test failed"
  [ "$AUTOMATED_MODE" -eq 1 ] && { echo "Aborting"; exit 1; }
  read -p "Continue? (y/n): " C; [ "$C" = "y" ] || [ "$C" = "Y" ] || exit 0
else
  echo "✓ Firmware valid"
fi

# Confirm
echo ""; echo "=== Ready to Upgrade $CUR → $VER ==="
[ "$AUTOMATED_MODE" -eq 0 ] && {
  if [ "$FACTORY_UPGRADE" -eq 1 ]; then
    echo "⚠️  FACTORY WIPES ALL SETTINGS!"
    read -p "Type YES: " C; [ "$C" = "YES" ] || exit 0
  else
    read -p "Proceed? (y/n): " C; [ "$C" = "y" ] || [ "$C" = "Y" ] || exit 0
  fi
}

# Upgrade
echo ""; echo "Upgrading... DO NOT UNPLUG!"; sleep 5
[ "$FACTORY_UPGRADE" -eq 1 ] && sysupgrade -v -F -n "$FW" || sysupgrade -v "$FW"

