#!/bin/sh
set -e 

echo "installing wget and some other stuff"
opkg update || { echo "opkg update failed"; exit 1; }

opkg install openssl-util ca-certificates  || { echo "Package install failed"; exit 1; }

if ! opkg list-installed | grep -q libustream; then
  opkg install libustream-mbedtls || { echo "libustream-mbedtls install failed"; exit 1; }
fi

# UBNT_AP: https://downloads.openwrt.org/releases/21.02.2/targets/ath79/generic/openwrt-21.02.2-ath79-generic-ubnt_unifiac-lr-squashfs-sysupgrade.bin
# https://downloads.openwrt.org/releases/21.02.2/targets/ath79/generic/sha256sums

# Mi Router 3G: https://downloads.openwrt.org/releases/21.02.2/targets/ramips/mt7621/openwrt-21.02.2-ramips-mt7621-xiaomi_mi-router-3g-squashfs-sysupgrade.bin
# https://downloads.openwrt.org/releases/21.02.2/targets/ramips/mt7621/sha256sums

# AX 3200
# https://downloads.openwrt.org/releases/24.10.3/targets/mediatek/mt7622/openwrt-24.10.3-mediatek-mt7622-xiaomi_redmi-router-ax6s-squashfs-sysupgrade.itb

cd /tmp

echo "create a backup file"
BACKUPFILE=backup-${HOSTNAME}-$(date +%F).tar.gz
umask 077
sysupgrade -b $BACKUPFILE || { echo "Backup creation failed"; exit 1; }

. /lib/functions/network.sh; network_find_wan NET_IF; network_get_ipaddr IP_ADDR "${NET_IF}"
read -p "Now copy the backup file to your computer by entering the following command on your terminal:"$'\n'"scp -O $USER@$IP_ADDR:/tmp/$BACKUPFILE ."$'\n'"Enter any key after you are finished."

read -p "Enter the Downloadlink [https://downloads.openwrt.org/releases/24.10.3/targets/mediatek/mt7622/openwrt-24.10.3-mediatek-mt7622-xiaomi_redmi-router-ax6s-squashfs-sysupgrade.itb]: " DOWNLOAD_LINK
DOWNLOAD_LINK=${DOWNLOAD_LINK:-https://downloads.openwrt.org/releases/24.10.3/targets/mediatek/mt7622/openwrt-24.10.3-mediatek-mt7622-xiaomi_redmi-router-ax6s-squashfs-sysupgrade.itb}

echo "Downloading firmware image..."
wget --no-check-certificate $DOWNLOAD_LINK || { echo "Download failed"; exit 1; }

FILENAME=$(basename "$DOWNLOAD_LINK")

read -p "Enter SHA256SUM: " SHA256SUM
if [ -z "$SHA256SUM" ]; then
  echo "No SHA256 checksum provided, aborting."
  exit 1
fi

#SHA256SUMS_LINK=${SHA256SUMS_LINK:-https://downloads.openwrt.org/releases/21.02.2/targets/ath79/generic/sha256sums}

echo "${SHA256SUM} *$FILENAME" > sha256sum

echo "Verifying SHA256 checksum..."
if ! sha256sum -c sha256sum; then
  echo "Checksum verification failed, aborting."
  exit 1
fi

echo "Checksum verified."

sysupgrade -T -f $BACKUPFILE $FILENAME 2>&1 > error.log

if [ $? -eq 0 ]; then
  echo "Upgrade test passed, proceeding with upgrade..."
  sysupgrade -v -c $FILENAME         # keep config and verbose output
else
  echo "Upgrade test failed, aborting upgrade!"
  cat error.log
  exit 1
fi
