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
- Updates the package list via `apk`
- Installs `luci-compat` and `luci-lib-ipkg` from the OpenWRT repo
- Downloads and installs `luci-theme-argon` and `luci-app-argon-config` from GitHub
- Installs `.ipk` packages with `--allow-untrusted` to avoid signature warnings
- Falls back to manual tar extraction if `opkg` is not available
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

- Default package links point to the latest known releases — you'll be prompted to confirm or override them
- Works on **OpenWRT 25.10+** (apk-based) as well as older versions with opkg
- The `luci-app-sqm` package is **not** installed automatically — add it separately if needed
