#!/bin/sh
# not sure so far if this is really needed:
# opkg list-installed | grep -q uclient-fetch || opkg install uclient-fetch
# opkg list-installed | grep -q libustream || opkg install libustream-mbedtls

# for devices with enough storage its possible to install an config app for the argon theme:
# opkg install luci-app-sqm
cd /tmp
read -p "Enter the download link of the luci app argon config [https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.2.9/luci-app-argon-config_0.9-20210309_all.ipk]"
LUCI_APP_ARGON_CONFIG_LINK=${LUCI_APP_ARGON_CONFIG_LINK:-https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.2.9/luci-app-argon-config_0.9-20210309_all.ipk}
LUCI_APP_ARGON_CONFIG_FILENAME=$(echo $LUCI_APP_ARGON_CONFIG_LINK | cut -d/ -f9)

wget --no-check-certificate $LUCI_APP_ARGON_CONFIG_LINK -O $LUCI_APP_ARGON_CONFIG_FILENAME
opkg install $LUCI_APP_ARGON_CONFIG_FILENAME

opkg update
opkg install luci-compat luci-lib-ipkg

rm $LUCI_APP_ARGON_CONFIG_FILENAME

read -p "Enter the download link of the luci argon theme [https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.2.9.4/luci-theme-argon-master_2.2.9.4_all.ipk]"
LUCI_ARGON_THEME_LINK=${LUCI_ARGON_THEME_LINK:-https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.2.9.4/luci-theme-argon-master_2.2.9.4_all.ipk}
LUCI_ARGON_THEME_FILENAME=$(echo $LUCI_ARGON_THEME_LINK | cut -d/ -f9)

wget --no-check-certificate $LUCI_ARGON_THEME_LINK -O $LUCI_ARGON_THEME_FILENAME
opkg install $LUCI_ARGON_THEME_FILENAME

rm $LUCI_ARGON_THEME_FILENAME
