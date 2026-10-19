# Automatic Tailscale restoration after sysupgrade

## Purpose

`Ensure-Tailscale.sh` restores Tailscale on APK-based OpenWrt after a sysupgrade while preserving the existing identity and preferences. It never runs `tailscale up`, `login`, `logout`, or `reset`.

The original bootstrap was live-verified on 18.10.2026. The current simplified install-only implementation is fixture-tested but has not been deployed or post-sysupgrade live-verified.

## Safety model

Before package operations, the script requires:

- the running kernel to match the kernel package in `/rom`;
- installed and `/rom` kernel package metadata to match;
- non-empty, matching active and `/rom` release metadata;
- matching active and `/rom` distribution feeds; and
- readable `/rom` repositories and available `/rom` signing keys.

`--check` performs only these read-only checks.

Under `/var/lock/post-sysupgrade-package-install.lock`, the script checks `tailscale`, `kmod-tun`, and `luci-app-tailscale-community` independently. Installed packages are never changed. Missing packages and required missing dependencies are requested from the `/rom` repositories and keys. The script first runs `apk add --simulate`, accepts only `Installing` progress actions with every requested package present, and then runs a separate `apk add`.

Argon restoration uses the same mkdir lock. This serializes the two restore scripts from their package-presence checks through installation. It does not lock out unrelated package-manager clients, so do not run package or firmware administration concurrently.

After restoration, the script verifies package presence, the TUN module file, `modprobe tun`, `/dev/net/tun`, and the native Tailscale service. It enables the service and starts it only when `tailscaled` is not already running. It reads only connection fields from `tailscale status --json`; a machine requiring login fails without changing identity or preferences.

The procd one-shot runs at boot and uses `start` on LAN, WAN, and WAN6 up events. It has no respawn loop, and link events do not restart or kill an active restoration.

## Installation

Place the checkout at `/root/FirmwareUpgradeOpenWRT`, then run:

```sh
cd /root/FirmwareUpgradeOpenWRT
./Install-Tailscale-Auto-Install.sh
```

The setup checks metadata before enabling the service and preserves only the checkout, Tailscale state directory, init script, and service symlink across sysupgrade. It does not preserve APK databases, feeds, release metadata, or kernel modules.

## Verification

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
shellcheck Ensure-Tailscale.sh Install-LuCI-Argon-Theme.sh \
  Install-Tailscale-Auto-Install.sh Install-Argon-Auto-Update.sh \
  Tailscale-Auto-Install.init Argon-Auto-Update.init
sh -n Ensure-Tailscale.sh Install-LuCI-Argon-Theme.sh \
  Install-Tailscale-Auto-Install.sh Install-Argon-Auto-Update.sh \
  Tailscale-Auto-Install.init Argon-Auto-Update.init
```

The fixture suite contains no more than 15 behavioral tests. It covers coherent read-only metadata checks, installed-package idempotence, missing-only installs, refusal of non-`Installing` simulated actions, checksum refusal, the shared lock, Tailscale identity retention, absence of login/reset commands, and procd start triggers. APK fixtures emit APK 3-style progress with padded counters and model simulation and add as separate calls.
