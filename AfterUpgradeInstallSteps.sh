opkg update
opkg install ca-bundle openssl-util ca-certificates wget git
opkg list-installed | grep -q uclient-fetch || opkg install uclient-fetch
opkg list-installed | grep -q libustream || opkg install libustream-mbedtls

opkg update
git clone git://github.com/tavinus/opkg-upgrade.git
cd opkg-upgrade
./opkg-upgrade.sh -i # installs the opkg-upgrade to /usr/sbin/opkg-upgrade
cd .. 
rm -r opkg-upgrade
opkg-upgrade -f
opkg install luci luci-ssl
service uhttpd restart
