#opkg update
#opkg install ca-certificates
#opkg list-installed | grep -q uclient-fetch || opkg install uclient-fetch
#opkg list-installed | grep -q libustream || opkg install libustream-mbedtls
#echo -e -n 'untrusted comment: LEDE usign key of Stan Grishin\nRWR//HUXxMwMVnx7fESOKO7x8XoW4/dRidJPjt91hAAU2L59mYvHy0Fa\n' > /tmp/stangri-repo.pub && opkg-key add /tmp/stangri-repo.pub
! grep -q 'stangri_repo' /etc/opkg/customfeeds.conf && echo 'src/gz stangri_repo https://raw.githubusercontent.com/stangri/openwrt-repo/master' >> /etc/opkg/customfeeds.conf
#opkg update
#opkg install git
g#it clone git://github.com/tavinus/opkg-upgrade.git
#cd opkg-upgrade
#./opkg-upgrade.sh -i
#cd .. 
#rm -r opkg-upgrade
opkg-upgrade -f
opkg install luci-theme-material-old luci-theme-material
