echo installing wget
opkg install openssl-util ca-certificates wget
opkg list-installed | grep -q libustream || opkg install libustream-mbedtls
echo "enter the downloadlink"
read DOWNLOAD_LINK
echo "enter sha256sums file"
read SHA256SUMS
echo "enter the backup file"
read BACKUPFILE
FILENAME=$(wget $DOWNLOAD_LINK -nv 2>&1 |cut -d\" -f2)
cd /tmp;wget $DOWNLOAD_LINK;
wget $SHA256SUMS
sha256sum -c sha256sums 2>/dev/null | if grep OK; then sysupgrade -c -o -v -k -f $BACKUPFILE $FILENAME; else echo "sum is not correct"; fi
