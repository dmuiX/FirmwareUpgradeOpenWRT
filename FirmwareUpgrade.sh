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
# update and install luci
opkg update
opkg install ca-bundle openssl-util ca-certificates wget git
opkg list-installed | grep -q uclient-fetch || opkg install uclient-fetch
opkg list-installed | grep -q libustream || opkg install libustream-mbedtls
echo -e -n 'untrusted comment: LEDE usign key of Stan Grishin\nRWR//HUXxMwMVnx7fESOKO7x8XoW4/dRidJPjt91hAAU2L59mYvHy0Fa\n' > /tmp/stangri-repo.pub && opkg-key add /tmp/stangri-repo.pub
! grep -q 'stangri_repo' /etc/opkg/customfeeds.conf && echo 'src/gz stangri_repo https://raw.githubusercontent.com/stangri/openwrt-repo/master' >> /etc/opkg/customfeeds.conf
opkg update
git clone git://github.com/tavinus/opkg-upgrade.git
cd opkg-upgrade
./opkg-upgrade.sh -i # installs the opkg-upgrade to /usr/sbin/opkg-upgrade
cd .. 
rm -r opkg-upgrade
opkg-upgrade -f
opkg install luci luci-ssl
service uhttpd restart
