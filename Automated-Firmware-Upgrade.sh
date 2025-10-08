#!/bin/sh
set -eE
cd /tmp

# Error handling
trap 'echo "ERROR at line ${LINENO}. Backup: ${BACKUP:-none}"; exit 1' ERR
trap 'rm -f releases.html sha256sums 2>/dev/null; grep -q " $SMB_MOUNT " /proc/mounts 2>/dev/null && umount -f "$SMB_MOUNT" 2>/dev/null || true' EXIT

ENV_FILE="/root/FirmwareUpgradeOpenWRT/.env"

if [ -f "$ENV_FILE" ]; then
  . "$ENV_FILE"
  echo "Loaded configuration from $ENV_FILE"
else
  cat << 'ENVEXAMPLE'
ERROR: Configuration file not found: /root/FirmwareUpgradeOpenWRT/.env

Create it with:
cat > /root/FirmwareUpgradeOpenWRT/.env << 'EOF'
SMB_SERVER=//192.168.1.5/openwrt-backups
SMB_MOUNT=/mnt/openwrt-backups
SMB_USER=openwrt-backup
SMB_PASSWORD=your-password-here
SMB_DOMAIN=WORKGROUP
TARGET=mediatek
SUBTARGET=mt7622
DEVICE_NAME=xiaomi_redmi-router-ax6s
FACTORY_UPGRADE=0
AUTOMATED_MODE=0
EOF
chmod 600 /root/FirmwareUpgradeOpenWRT/.env
ENVEXAMPLE
  exit 1
fi

# Validate vars
for V in SMB_SERVER SMB_MOUNT SMB_USER SMB_PASSWORD TARGET SUBTARGET DEVICE_NAME; do
  eval "[ -z \"\$$V\" ]" && { echo "ERROR: $V not set"; exit 1; }
done

FACTORY_UPGRADE="${FACTORY_UPGRADE:-0}"; AUTOMATED_MODE="${AUTOMATED_MODE:-0}"

echo "=== OpenWrt Safe Upgrade ==="
echo "Device: $DEVICE_NAME ($TARGET/$SUBTARGET)"

if [ "$FACTORY_UPGRADE" -eq 1 ]; then
  TYPE="factory"; EXT="bin"; echo "Mode: FACTORY (wipes config)"
else
  TYPE="squashfs-sysupgrade"; EXT="itb"; echo "Mode: SYSUPGRADE (keeps config)"
fi

# Download function
dl() {
  _url="$1"; _output="$2"; _show_progress="${3:-}"
  
  if ! wget --spider --max-redirect=3 --timeout=10 --tries=2 "$_url" >/dev/null 2>&1; then
    echo "ERROR: Cannot reach $_url"; return 1
  fi
  
  rm -f "$_output" "$_output.tmp" 2>/dev/null || true
  
  if [ -n "$_show_progress" ]; then
    wget --timeout=30 --tries=3 --waitretry=5 --progress=dot:giga -O "$_output" "$_url" || return 1
  else
    wget --timeout=30 --tries=3 --waitretry=5 -q -O "$_output" "$_url" || return 1
  fi
  
  [ ! -f "$_output" ] && { echo "ERROR: Download failed"; return 1; }
  _sz=$(stat -c%s "$_output" 2>/dev/null || echo 0)
  [ "$_sz" -lt 1024 ] && { echo "ERROR: File too small"; rm -f "$_output"; return 1; }
  
  return 0
}

# Check space - validate numeric including negatives
AVAIL=$(df /tmp | awk 'NR==2 {print $(NF-2)}')
case "$AVAIL" in
  ''|-*|*[!0-9]*) echo "ERROR: Cannot determine free space"; exit 1 ;;
esac
[ "$AVAIL" -lt 25600 ] && { echo "ERROR: Low space in /tmp (need 25MB, have $((AVAIL/1024))MB)"; exit 1; }

# Install packages
if ! opkg list-installed 2>/dev/null | grep -q '^kmod-fs-cifs '; then
  echo "Installing packages..."
  opkg update || { echo "ERROR: opkg update failed"; exit 1; }
  opkg install openssl-util ca-certificates kmod-fs-cifs libustream-mbedtls || exit 1
fi

# Detect version
echo "Detecting latest version..."
dl "https://downloads.openwrt.org/releases/" "releases.html" || exit 1

# BusyBox-compatible sort
VER=$(grep -oE 'href="[0-9]{2,}\.[0-9]{1,2}\.[0-9]{1,2}/"' releases.html | head -5 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -t. -k1,1n -k2,2n -k3,3n -r | head -1)
[ -z "$VER" ] && { echo "ERROR: Cannot detect version"; exit 1; }

CUR=$(grep '^DISTRIB_RELEASE=' /etc/openwrt_release 2>/dev/null | cut -d= -f2 | tr -d "'" | tr -d '"' | sed 's/^ *//;s/ *$//')
[ -z "$CUR" ] && CUR="unknown"

echo "Current: $CUR → Target: $VER"

if [ "$CUR" = "$VER" ]; then
  echo "Already on latest version"; exit 0
elif echo "$CUR" | grep -qE 'SNAPSHOT|^r[0-9]|unknown'; then
  echo "Upgrading from development version"
else
  CUR_NORM=$(echo "$CUR" | sed 's/\.0\+\([1-9]\)/.\1/g')
  VER_NORM=$(echo "$VER" | sed 's/\.0\+\([1-9]\)/.\1/g')
  [ "$CUR_NORM" = "$VER_NORM" ] && { echo "Already on version $VER"; exit 0; }
fi

BASE="https://downloads.openwrt.org/releases/${VER}/targets/${TARGET}/${SUBTARGET}"
FW_NAME="openwrt-${VER}-${TARGET}-${SUBTARGET}-${DEVICE_NAME}-${TYPE}.${EXT}"

# Backup
echo "Creating backup..."
BAK="backup-${HOSTNAME}-$(date +%F-%H%M%S).tar.gz"
sysupgrade -b "$BAK" || { echo "ERROR: Backup failed"; exit 1; }

BAK_SIZE=$(stat -c%s "$BAK" 2>/dev/null || echo 0)
[ "$BAK_SIZE" -lt 5120 ] && { echo "ERROR: Backup too small"; rm -f "$BAK"; exit 1; }

if ! tar -tzf "$BAK" >/dev/null 2>&1; then
  echo "ERROR: Backup corrupted"; rm -f "$BAK"; exit 1
fi

if ! tar -tzf "$BAK" 2>/dev/null | grep -qE '^(\./)?etc/config/'; then
  echo "ERROR: Backup missing config"; rm -f "$BAK"; exit 1
fi

echo "✓ Backup: $BAK ($((BAK_SIZE/1024))KB)"
BACKUP="$BAK"

# Upload to SMB
echo "Uploading backup..."
SRV=$(echo "$SMB_SERVER" | sed 's|//||' | cut -d/ -f1)

if grep -q " $SMB_MOUNT " /proc/mounts 2>/dev/null; then
  umount -f "$SMB_MOUNT" 2>/dev/null || true; sleep 1
fi

if ping -c1 -W2 "$SRV" >/dev/null 2>&1; then
  mkdir -p "$SMB_MOUNT"
  
  if mount -t cifs "$SMB_SERVER" "$SMB_MOUNT" -o username="$SMB_USER",password="$SMB_PASSWORD",domain="${SMB_DOMAIN:-WORKGROUP}",rw,soft,timeout=15 2>/dev/null; then
    
    if cp "$BAK" "$SMB_MOUNT/" 2>/dev/null; then
      SMB_SIZE=$(stat -c%s "$SMB_MOUNT/$BAK" 2>/dev/null || echo 0)
      [ "$SMB_SIZE" -eq "$BAK_SIZE" ] && echo "✓ Uploaded to SMB" || echo "WARNING: Upload size mismatch"
    else
      echo "WARNING: Upload failed"
    fi
    
    umount "$SMB_MOUNT" 2>/dev/null || umount -f "$SMB_MOUNT" 2>/dev/null || true
  else
    echo "WARNING: Cannot mount SMB"
  fi
else
  echo "WARNING: SMB unreachable"
fi

# Check space
AVAIL=$(df /tmp | awk 'NR==2 {print $(NF-2)}')
case "$AVAIL" in ''|-*|*[!0-9]*) AVAIL=0 ;; esac
[ "$AVAIL" -lt 15360 ] && { echo "ERROR: Low space after backup"; exit 1; }

# Download checksums
echo "Downloading checksums..."
dl "${BASE}/sha256sums" "sha256sums" || exit 1
[ -s sha256sums ] || { echo "ERROR: Checksums empty"; exit 1; }

# Extract checksum - fixed quote mixing
CHK=$(awk '/[*]'"${DEVICE_NAME}-${TYPE}\.${EXT}"'$/ {print $1}' sha256sums)

if [ -z "$CHK" ]; then
  echo "ERROR: Checksum not found for ${DEVICE_NAME}-${TYPE}.${EXT}"
  echo "Available firmware:"
  awk '/[*]'"${DEVICE_NAME}-"'/ {print "  "$2}' sha256sums | sed 's/^[*]//' || echo "  None"
  exit 1
fi

if ! echo "$CHK" | grep -qE '^[a-f0-9]{64}$'; then
  echo "ERROR: Invalid checksum: $CHK"; exit 1
fi

CHK_SHORT=$(echo "$CHK" | cut -c1-16)
echo "✓ Checksum: ${CHK_SHORT}..."

# Download firmware
echo "Downloading firmware..."
dl "${BASE}/${FW_NAME}" "fw_temp" "progress" || exit 1

FW_SIZE=$(stat -c%s "fw_temp" 2>/dev/null || echo 0)
[ "$FW_SIZE" -lt 3000000 ] && { echo "ERROR: Firmware too small"; rm -f "fw_temp"; exit 1; }
echo "✓ Size: $((FW_SIZE/1024/1024))MB"

if dd if="fw_temp" bs=100 count=1 2>/dev/null | grep -qiE '<html|<!doctype'; then
  echo "ERROR: Downloaded HTML"; rm -f "fw_temp"; exit 1
fi

echo "Verifying checksum..."
FW_CHK=$(sha256sum "fw_temp" | awk '{print $1}')
if [ "$FW_CHK" != "$CHK" ]; then
  echo "CRITICAL: CHECKSUM MISMATCH!"
  echo "Expected: $CHK"
  echo "Got:      $FW_CHK"
  rm -f "fw_temp"; exit 1
fi
echo "✓ Checksum verified"

# Test firmware
echo "Testing firmware..."
set +e
TEST_OUT=$(sysupgrade -T "fw_temp" 2>&1)
TEST_RC=$?
set -e

if [ $TEST_RC -eq 0 ]; then
  echo "✓ Firmware compatible"
elif echo "$TEST_OUT" | grep -qE 'invalid option.*-T|unrecognized option.*-T'; then
  echo "⚠ Test not supported"
else
  echo "WARNING: Test failed: $TEST_OUT"
  
  if [ "$AUTOMATED_MODE" -eq 1 ]; then
    echo "Aborting"; rm -f "fw_temp"; exit 1
  fi
  
  printf "Continue? (y/n): "
  read -r ANS || ANS="n"
  [ "$ANS" = "y" ] || [ "$ANS" = "Y" ] || { rm -f "fw_temp"; exit 0; }
fi

# Confirmation
echo ""
echo "=== Ready: $CUR → $VER ==="
echo "Firmware: $FW_NAME ($((FW_SIZE/1024/1024))MB)"
echo "Backup: $BAK ($((BAK_SIZE/1024))KB)"

if [ "$AUTOMATED_MODE" -eq 0 ]; then
  if [ "$FACTORY_UPGRADE" -eq 1 ]; then
    echo "⚠️  FACTORY WIPES ALL SETTINGS!"
    printf "Type YES: "
    read -r CONFIRM || CONFIRM=""
    [ "$CONFIRM" = "YES" ] || { rm -f "fw_temp"; exit 0; }
  else
    printf "Proceed? (y/n): "
    read -r CONFIRM || CONFIRM="n"
    [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ] || { rm -f "fw_temp"; exit 0; }
  fi
fi

# Final space check
AVAIL=$(df /tmp | awk 'NR==2 {print $(NF-2)}')
case "$AVAIL" in ''|-*|*[!0-9]*) AVAIL=0 ;; esac
[ "$AVAIL" -lt 5120 ] && { echo "ERROR: Low space"; rm -f "fw_temp"; exit 1; }

# Prepare and disable trap
mv "fw_temp" "fw_final" || { echo "ERROR: Cannot prepare"; exit 1; }
trap - EXIT

echo "Flushing buffers..."
sync; sleep 3

echo "Starting upgrade... DO NOT UNPLUG!"
sleep 2

if [ "$FACTORY_UPGRADE" -eq 1 ]; then
  sysupgrade -v -n "fw_final"
else
  sysupgrade -v "fw_final"
fi

