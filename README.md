# FirmwareUpgradeOpenWRT
- A short bash script to run a firmware upgrade on an OpenWRT-Router
- first install some requirements:
  opkg install ca-bundle git-http wget grep
- Clone the git and run it directly on the router with ./FirmwareUpgrade.sh
- It asks for a downloadlink (sysupgrade.bin) and for the sha256sums file
- for a mi router 3g it can be found here: https://downloads.openwrt.org/releases/18.06.2/targets/ramips/mt7621/
# AfterFirmwareInstall
- The AfterFirmwareInstall.sh contains some commands that I find useful
- Basically it is adding a repository and the opkg-upgrade command and is installing the luci material theme and the luci material theme old and the argon theme

# Using it:
cd /tmp && wget https://raw.githubusercontent.com/dmuiX/FirmwareUpgradeOpenWRT/master/FirmwareUpgrade.sh -O upgrade.sh && chmod +x upgrade.sh && ./upgrade.sh
cd /tmp && wget https://raw.githubusercontent.com/dmuiX/FirmwareUpgradeOpenWRT/master/AfterUpgradeInstallSteps.sh -O theme.sh && chmod +x theme.sh && ./theme.sh
