opkg update
opkg install ca-bundle openssl-util ca-certificates wget git
opkg list-installed | grep -q uclient-fetch || opkg install uclient-fetch
opkg list-installed | grep -q libustream || opkg install libustream-mbedtls
wget --no-check-certificate https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.2.5/luci-theme-argon_2.2.5-20200914_all.ipk
opkg install luci-theme-argon*.ipk
opkg update
opkg install luci luci-ssl luci-compat luci-app-sqm
wget https://github.com/jerrykuku/luci-app-argon-config/releases/download/v0.8-beta/luci-app-argon-config_0.8-beta_all.ipk
opkg install luci-app-argon-config_0.8-beta_all.ipk
rm luci-theme-argon_2.2.5-20200914_all.ipk luci-app-argon-config_0.8-beta_all.ipk openwrt-19.[0-9][0-9].[0-9]-ramips-mt7621-xiaomi_mir3g-squashfs-sysupgrade.bin
service uhttpd restart
