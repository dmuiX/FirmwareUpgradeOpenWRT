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
- Downloads the single APK needed for a fresh Argon 3 installation: `luci-theme-argon-3.0.0-r2.apk`
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

---

## 📝 Notes

- The Argon installer is for firmware that natively uses APK v3 (`apk-tools` 3.x). For native `opkg` firmware, use the `.ipk` asset and the installation instructions from the [Argon release](https://github.com/jerrykuku/luci-theme-argon/releases/latest).
- Do not install `luci-app-argon-config` manually on a fresh Argon 3 setup. The script uses this empty compatibility package only when it detects an existing Argon 2 installation that must be migrated.
- The installer prompts for each required download URL and offers the matching Argon 3 package as its default.
- The `luci-app-sqm` package is **not** installed automatically — add it separately if needed
