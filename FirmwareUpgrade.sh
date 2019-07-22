echo installing wget
opkg install ca-bundles openssl-util ca-certificates libustream-openssl wget
echo "enter the downloadlink"
read DOWNLOAD_LINK
echo "enter sha256sums file"
read SHA256SUMS
filename=$(wget $DOWNLOAD_LINK -nv 2>&1 |cut -d\" -f2)
cd /tmp;wget $DOWNLOAD_LINK;
wget $SHA256SUMS
sha256sum -c sha256sums 2>/dev/null | if grep OK; then sysupgrade -v $filename; else echo "sum is not correct"; fi
