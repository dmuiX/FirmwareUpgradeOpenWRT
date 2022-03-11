opkg update
opkg install luci-compat luci-lib-ipkg
# opkg list-installed | grep -q uclient-fetch || opkg install uclient-fetch
# opkg list-installed | grep -q libustream || opkg install libustream-mbedtls
# luci-app-sqm

cd /tmp
read -p "Enter the download link of the luci app argon config [https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.2.9/luci-app-argon-config_0.9-20210309_all.ipk]"
LUCI_APP_ARGON_CONFIG_LINK=${LUCI_APP_ARGON_CONFIG_LINK:-https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.2.9/luci-app-argon-config_0.9-20210309_all.ipk}
LUCI_APP_ARGON_CONFIG_FILENAME=$(echo $LUCI_APP_ARGON_CONFIG_LINK | cut -d/ -f9)

wget --no-check-certificate $LUCI_APP_ARGON_CONFIG_LINK -O $LUCI_APP_ARGON_CONFIG_FILENAME
opkg install $LUCI_APP_ARGON_CONFIG_FILENAME

rm $LUCI_APP_ARGON_CONFIG_FILENAME 

read -p "Enter the download link of the luci app argon config [https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.2.9/luci-theme-argon_2.2.9-20211016-1_all.ipk]"
LUCI_ARGON_THEME_LINK=${LUCI_ARGON_THEME_LINK:-https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.2.9/luci-theme-argon_2.2.9-20211016-1_all.ipk}
LUCI_ARGON_THEME_FILENAME=$(echo $LUCI_ARGON_THEME_LINK | cut -d/ -f9)

wget --no-check-certificate $LUCI_ARGON_THEME_LINK -O $LUCI_ARGON_THEME_FILENAME
opkg install $LUCI_ARGON_THEME_FILENAME

rm $LUCI_ARGON_THEME_FILENAME
