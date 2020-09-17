opkg update
opkg install ca-bundle openssl-util ca-certificates wget git
opkg list-installed | grep -q uclient-fetch || opkg install uclient-fetch
opkg list-installed | grep -q libustream || opkg install libustream-mbedtls
wget --no-check-certificate https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.2.5/luci-theme-argon_2.2.5-20200914_all.ipk
opkg install luci-theme-argon*.ipk
opkg update
git clone git://github.com/tavinus/opkg-upgrade.git
cd opkg-upgrade
./opkg-upgrade.sh -i # installs the opkg-upgrade to /usr/sbin/opkg-upgrade
cd .. 
rm -r opkg-upgrade
opkg-upgrade -f
opkg install luci luci-ssl
service uhttpd restart
