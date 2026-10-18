# 🛠️ FirmwareUpgradeOpenWRT

Scripts for upgrading OpenWRT firmware and setting up the LuCI Argon theme.

> ⚠️ **OpenWRT 25.10+** uses `apk` as package manager (replaces `opkg`). The scripts here support both.

---

## 📦 Setup on the Router

First, install the required tools:

```sh
apk add git git-http
```

Then clone the repo:

```sh
cd /tmp && git clone https://github.com/dmuiX/FirmwareUpgradeOpenWRT
```

Or run the scripts directly without cloning (see below).

---

## 🚀 Firmware Upgrade

Runs an interactive sysupgrade — asks for a download link to a `sysupgrade.bin` and the matching `sha256sums` file.

**Run directly on the router:**

```sh
cd /tmp \
  && wget https://raw.githubusercontent.com/dmuiX/FirmwareUpgradeOpenWRT/master/Interactive-Firmware-Upgrade.sh -O upgrade.sh \
  && chmod +x upgrade.sh \
  && ./upgrade.sh
```

Sysupgrade images can be found at:
https://downloads.openwrt.org/releases/

---

## 🎨 Install LuCI Argon Theme

Installs the [Argon theme](https://github.com/jerrykuku/luci-theme-argon) for LuCI and sets it as the default.

**What it does:**
- Queries the GitHub Releases API and selects the newest `luci-theme-argon-*.apk` asset automatically
- Skips the download when that exact version is already installed
- Migrates an installed Argon 2 configuration package, or removes its stale APK world entry when a firmware backup restored the request without the package
- Installs APKs with `apk add --allow-untrusted`
- Uses Argon 3's configuration UI, which is integrated into the theme package
- Sets Argon as the active theme via `uci` and restarts `uhttpd`

**Run directly on the router:**

```sh
cd /tmp \
  && wget https://raw.githubusercontent.com/dmuiX/FirmwareUpgradeOpenWRT/master/Install-LuCI-Argon-Theme.sh -O theme.sh \
  && chmod +x theme.sh \
  && ./theme.sh
```

### Automatic restore and updates after firmware upgrades

When this repository is located at `/root/FirmwareUpgradeOpenWRT`, enable the included procd service once:

```sh
cd /root/FirmwareUpgradeOpenWRT
./Install-Argon-Auto-Update.sh
```

The service runs after boot and whenever the WAN interface comes up. It uses the installer's non-interactive mode to restore Argon after a firmware flash and to install newer GitHub releases. If the latest version is already installed, it exits without downloading the APK.

The setup records the repository, service and enabled-service symlink in `/etc/sysupgrade.conf` so they survive subsequent firmware flashes.

Check its output with:

```sh
logread -e Install-LuCI-Argon-Theme.sh
```

---

## 📝 Notes

- The Argon installer is for firmware that natively uses APK v3 (`apk-tools` 3.x). For native `opkg` firmware, use the `.ipk` asset and the installation instructions from the [Argon release](https://github.com/jerrykuku/luci-theme-argon/releases/latest).
- Do not install `luci-app-argon-config` manually on a fresh Argon 3 setup. The script uses this empty compatibility package only when it detects an existing Argon 2 installation that must be migrated.
- The interactive installer prompts for each required download URL and offers the latest matching Argon release asset as its default. The automatic service uses that latest asset without prompting.
- The `luci-app-sqm` package is **not** installed automatically — add it separately if needed
