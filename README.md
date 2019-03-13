# FirmwareUpgradeOpenWRT
- A short bash script to run a firmware upgrade on an OpenWRT-Router
- Just run it with ./FirmwareUpgrade.sh
- It asks for a downloadlink and for the sha256sums file
- Both can be found here: https://downloads.openwrt.org/releases/18.06.2/targets/ramips/mt7621/
- The AfterFirmwareInstall.sh contains some commands that I find useful
- it is adding a repository and the opkg-upgrade command and is installing the luci material theme and the luci material theme old
