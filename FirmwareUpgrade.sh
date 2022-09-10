#!/bin/sh
echo "installing wget and some other stuff"
opkg update
opkg install openssl-util ca-certificates
opkg list-installed | grep -q libustream || opkg install libustream-mbedtls

# UBNT_AP: https://downloads.openwrt.org/releases/21.02.2/targets/ath79/generic/openwrt-21.02.2-ath79-generic-ubnt_unifiac-lr-squashfs-sysupgrade.bin
# https://downloads.openwrt.org/releases/21.02.2/targets/ath79/generic/sha256sums

# Mi Router 3G: https://downloads.openwrt.org/releases/21.02.2/targets/ramips/mt7621/openwrt-21.02.2-ramips-mt7621-xiaomi_mi-router-3g-squashfs-sysupgrade.bin
# https://downloads.openwrt.org/releases/21.02.2/targets/ramips/mt7621/sha256sums

cd /tmp
echo "create a backup file"
BACKUPFILE=backup-${HOSTNAME}-$(date +%F).tar.gz
umask go=
sysupgrade -b $BACKUPFILE

. /lib/functions/network.sh; network_find_wan NET_IF; network_get_ipaddr IP_ADDR "${NET_IF}"
read -p "Now copy the backup file to your computer by entering the following command on your terminal:"$'\n'"scp $USER@$IP_ADDR:/tmp/$BACKUPFILE ."$'\n'"Enter any key after you are finished."

read -p "Enter the Downloadlink [https://downloads.openwrt.org/releases/21.02.2/targets/ath79/generic/openwrt-21.02.2-ath79-generic-ubnt_unifiac-lr-squashfs-sysupgrade.bin]: " DOWNLOAD_LINK
DOWNLOAD_LINK=${DOWNLOAD_LINK:-https://downloads.openwrt.org/releases/21.02.2/targets/ath79/generic/openwrt-21.02.2-ath79-generic-ubnt_unifiac-lr-squashfs-sysupgrade.bin}
wget --no-check-certificate $DOWNLOAD_LINK
FILENAME=$(echo $DOWNLOAD_LINK | cut -d/ -f9)

read -p "Enter SHA256SUM: " SHA256SUM
echo "${SHA256SUM} *$FILENAME" > sha256sum
#SHA256SUMS_LINK=${SHA256SUMS_LINK:-https://downloads.openwrt.org/releases/21.02.2/targets/ath79/generic/sha256sums}

#wget --no-check-certificate $SHA256SUMS_LINK
#SHA256SUMS=$(echo $SHA256SUMS_LINK | cut -d/ -f9)
sha256sum -c sha256sum 2>/dev/null | if grep OK; then sysupgrade -T -f $BACKUPFILE $FILENAME 2>&1 > error.log; if [[ $? -eq 0 ]]; then sysupgrade -c -o -v -k -f $BACKUPFILE $FILENAME; else cat error.log; fi; else echo "sum is not correct"; fi
