echo installing wget
opkg install ca-bundles openssl-util ca-certificates wget
opkg list-installed | grep -q libustream || opkg install libustream-mbedtls
echo "enter the downloadlink"
read DOWNLOAD_LINK
echo "enter sha256sums file"
read SHA256SUMS
filename=$(wget $DOWNLOAD_LINK -nv 2>&1 |cut -d\" -f2)
cd /tmp;wget $DOWNLOAD_LINK;
wget $SHA256SUMS
sysupgrade -b backup.tar.gz
sha256sum -c sha256sums 2>/dev/null | if grep OK; then sysupgrade -f backup.tar.gz -v $filename; else echo "sum is not correct"; fi
