#!/bin/sh

opkg update
opkg install luci-compat luci-lib-ipkg

read -p "Enter the download link of the luci argon theme [https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.3/luci-theme-argon_2.3_all.ipk]"
LUCI_ARGON_THEME_LINK=${LUCI_ARGON_THEME_LINK:-https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.3.1/luci-theme-argon_2.3.1_all.ipk}
LUCI_ARGON_THEME_FILENAME=$(echo $LUCI_ARGON_THEME_LINK | cut -d/ -f9)

wget --no-check-certificate $LUCI_ARGON_THEME_LINK -O $LUCI_ARGON_THEME_FILENAME
opkg install $LUCI_ARGON_THEME_FILENAME

rm $LUCI_ARGON_THEME_FILENAME

# for devices with enough storage its possible to install an config app for the argon theme:

read -p "Enter the download link of the luci app argon config [https://github.com/jerrykuku/luci-app-argon-config/releases/download/v0.9/luci-app-argon-config_0.9_all.ipk]"
LUCI_APP_ARGON_CONFIG_LINK=${LUCI_APP_ARGON_CONFIG_LINK:-https://github.com/jerrykuku/luci-app-argon-config/releases/download/v0.9/luci-app-argon-config_0.9_all.ipk}
LUCI_APP_ARGON_CONFIG_FILENAME=$(echo $LUCI_APP_ARGON_CONFIG_LINK | cut -d/ -f9)

wget --no-check-certificate $LUCI_APP_ARGON_CONFIG_LINK -O $LUCI_APP_ARGON_CONFIG_FILENAME
opkg install $LUCI_APP_ARGON_CONFIG_FILENAME luci-app-sqm

rm $LUCI_APP_ARGON_CONFIG_FILENAME
