# 🛠️ FirmwareUpgradeOpenWRT

Scripts for upgrading OpenWrt firmware and restoring selected packages after sysupgrade.

> The Argon and Tailscale restoration scripts require APK-based OpenWrt with a coherent immutable `/rom` baseline. They do not support `opkg`.

## Firmware upgrade

`Interactive-Firmware-Upgrade.sh` prompts for a sysupgrade image and its checksum file. Images are available from <https://downloads.openwrt.org/releases/>.

```sh
cd /tmp
wget https://raw.githubusercontent.com/dmuiX/FirmwareUpgradeOpenWRT/master/Interactive-Firmware-Upgrade.sh -O upgrade.sh
chmod +x upgrade.sh
./upgrade.sh
```

## LuCI Argon restoration

`Install-LuCI-Argon-Theme.sh`:

- checks the running kernel, installed kernel metadata, release metadata, and feeds against `/rom`;
- leaves an installed `luci-theme-argon` package untouched;
- otherwise downloads the pinned 3.0.0-r2 APK and verifies its SHA-256 checksum;
- simulates the add and continues only when the sole action is installing that package;
- performs a separate add under the shared restoration lock; and
- activates Argon, restarting `uhttpd` only when the configured theme changes.

It is a restore script, not an updater. It never upgrades, downgrades, reinstalls, replaces, or removes an installed package.

```sh
cd /root/FirmwareUpgradeOpenWRT
./Install-LuCI-Argon-Theme.sh
```

`Install-Argon-Auto-Update.sh` installs the procd one-shot for boot and LAN/WAN-up restoration.

## Tailscale restoration

See [Tailscale-Auto-Install.md](Tailscale-Auto-Install.md). The bootstrap restores only missing `tailscale` and `kmod-tun` packages plus required missing dependencies. It preserves the existing identity and preferences and never logs in, logs out, or resets Tailscale.

## Notes

- The two restore scripts use `/var/lock/post-sysupgrade-package-install.lock` to serialize their presence check, simulation, and add operations.
- The lock coordinates these scripts only. Do not run other package administration concurrently.
- `luci-app-sqm` is not installed automatically.
