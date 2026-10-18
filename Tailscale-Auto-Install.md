# Automatic Tailscale restoration after sysupgrade

## Status — enabled and live-verified (2026-10-18)

The bootstrap is installed at `/etc/init.d/tailscale-auto-install`, enabled for
boot/WAN-up, and has completed successfully through real procd execution. The
native Tailscale service is enabled and connected using the existing login.

Live gates passed:

- Running kernel, ROM kernel and APK kernel package agree at 6.12.112, including
  the ROM ABI identifier. No installed kmod remains on the old 6.12.74 version.
- `/dev/net/tun` exists; TUN is loaded; BackendState is Running and Self.Online is
  true. A real `tailscale ping` to an online tailnet peer succeeded.
- Direct LuCI HTTPS and LuCI through Traefik return HTTP 200 with TLS verification.
- Protected network/firewall/DHCP/wireless/Tailscale/uhttpd config and HTTPS
  certificate/key hashes are unchanged. Boot identity is unchanged: no router
  reboot or firmware flash was performed, and no new login/reset was requested.
- A second real procd `start` produced another successful bootstrap execution
  without changing the native tailscaled PID. The installation lock was cleaned.
- The real sysupgrade backup manifest retains settings, identity, SSH and HTTPS
  material, while excluding release metadata, APK state/feeds, module payload
  configuration and obsolete opkg feeds.

A full firmware upgrade/reboot was deliberately **not** tested. The next planned
upgrade still requires its own post-upgrade live connectivity gate. These checks
prove the current restoration/entrypoint, not every possible future firmware.

## Root cause and completed repair

The immutable ROM was 25.12.6 / kernel 6.12.112, but `/etc/openwrt_release` still
reported 24.10.4. Distribution feeds pointed at 25.12.1, and active APK kernel/kmod
packages were 6.12.74. The preservation policy included all of `/etc`; the legacy
upgrade command also used `-c`, retaining changed firmware/package metadata.
The exact historical transaction which installed the old modules is not proven.

After a protected backup, release/version metadata and distribution feeds were
restored from `/rom`. A reviewed, signed-package transaction brought the kernel
**package bookkeeping** and 63 kmod packages to the already-running kernel ABI;
no kernel image was flashed. The primary download server failed on some package
payloads, so the remaining 17 package repairs completed through the HTTPS RWTH
mirror using the original ROM signing keys. No force or unsigned-install flags
were used. Persistent distribution feeds remain the ROM defaults.

`/etc/sysupgrade.conf` now explicitly preserves user settings/state rather than
all of `/etc`. Network settings, SSH host keys, Tailscale state, existing ACME
state, RADIUS/SQM settings, custom HTTPS files, custom startup scripts, `/root`
and `/usr/local` remain covered. Firmware metadata, APK database/world/feeds and
package-owned Argon payloads are not explicitly preserved. Package-owned modified
conffiles are still selected normally by sysupgrade.

`Interactive-Firmware-Upgrade.sh` no longer adds `-c`. Its other pre-existing
legacy opkg provisioning/image defaults were not modernized, and the script was
not executed: do not treat this change as approval of that legacy script as a
complete APK-era firmware upgrade tool. Use a separately reviewed upgrade path.
Existing uncommitted Argon installer/service changes were preserved unchanged.

Protected before-state and repair evidence are retained on the management host,
outside this repository (directory mode 0700, backup files 0600). They contain
sensitive configuration and must never be published. Do not restore an old APK
database alone over changed package payloads; recovery must be coherent.

## Files and behavior

- `Ensure-Tailscale.sh`: preflight, signed package restoration, module loading,
  native service enable/start and bounded connection check.
- `Tailscale-Auto-Install.init`: procd-managed one-shot on boot and WAN/WAN6-up.
- `Install-Tailscale-Auto-Install.sh`: idempotent registration/preservation setup;
  refuses activation against mismatched firmware/package metadata.

APK-based stock OpenWrt with `/rom`, module-based TUN and standard distribution
feeds is required. A loaded TUN device alone does not hide a missing module file
needed for the next boot; custom built-in-TUN kernels need separate review.
Before installation, the helper compares the running kernel, ROM kernel package,
installed kernel package, release metadata and distribution feed file. It refuses
incompatible solver plans and never pins an old kernel version in APK world.
The kernel independently verifies module ABI during `modprobe tun`.

If the primary source fails, a one-time HTTPS RWTH mirror attempt changes only
transport hostname, not release, architecture, ABI or signing authority. It is
based on the ROM feed paths and uses ROM keys. Persistent feed configuration is
not changed. Signature failure or a kernel-change plan is never bypassed.
Unsupported source layouts require review instead of automatic URL rewriting.

Healthy repeated runs do not reinstall packages or restart tailscaled. Existing
identity, routes, DNS and other preferences are retained: no automatic
`tailscale up`, `login`, `logout` or reset. Only BackendState and Self.Online are
read from status JSON; complete status/state/keys are not logged. A machine which
needs login is reported as such rather than silently registered.

Before installing, the helper waits up to 120 seconds for the existing Argon
procd job to finish, and uses APK's native 120-second lock wait for package
operations. It does not change or interrupt the Argon installer.

Concurrent attempts are serialized by a lock. The helper cleans owned temporary
mirror files and the lock on exit/failure/TERM; a stale lock after SIGKILL fails
closed and needs investigation. The service uses WAN-up `start` events, not a
WAN-down `restart` that could kill an active APK transaction. It is not an
unbounded respawn loop or periodic retry timer. Do not run package/firmware
administration concurrently. An APK solver preview is not an atomic lock across
unrelated package-manager processes.

This bootstrap does not rebuild an arbitrary broken package database or flash
firmware. An image already containing `tailscale` and matching `kmod-tun` remains
preferable where practical; restoration is a recovery mechanism.

## Manual checks / setup

Keep the checkout at `/root/FirmwareUpgradeOpenWRT`. The default state directory
`/etc/tailscale` and `/etc/config/tailscale` are preserved. Custom state paths need
separate review.

```sh
cd /root/FirmwareUpgradeOpenWRT
./Ensure-Tailscale.sh --check             # read-only metadata check
./Install-Tailscale-Auto-Install.sh       # register/enable after passing preflight
logread -e Ensure-Tailscale
```

Registration alone is not proof of a connected client. Check actual service/job
exit status, TUN, control connection and a suitable peer path separately.

## Automated verification

```sh
shellcheck Ensure-Tailscale.sh Install-Tailscale-Auto-Install.sh Tailscale-Auto-Install.init
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
```

23 tests exercise real shell entrypoints/procd wiring against disposable fixtures:
installation, TUN loading, backend connection, idempotence, identity retention,
ABI/release/feed rejection, solver kernel-change refusal, update/module failures,
missing login, locking, setup/preservation behavior, boot/WAN hooks, HTTPS mirror
fallback without persistent feed changes, mirror signature failure, Argon-job coordination/timeouts, loaded-TUN versus
persistent module-file checks, and the removed broad `-c` preservation flag. Fixture tests are complemented by the real
restoration and repeated procd execution documented above.
