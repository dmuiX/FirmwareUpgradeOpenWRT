"""Run real shell entrypoints against disposable OpenWrt/package-manager fixtures."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
ROM_KERNEL = "6.12.112~testabi-r1"


class TailscaleRestoreTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="openwrt-tailscale-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.events = self.root / "events"
        self.env = os.environ.copy()
        self.env.update(
            PATH=str(self.bin) + os.pathsep + self.env["PATH"],
            TEST_ROOT=str(self.root), TEST_PYTHON=sys.executable,
            TEST_ROM_KERNEL=ROM_KERNEL, TMPDIR=str(self.root / "tmp"),
        )
        for prefix in ("etc/apk/repositories.d", "rom/etc/apk/repositories.d", "etc/init.d", "lock", "modules/6.12.112", "repo", "tmp"):
            (self.root / prefix).mkdir(parents=True, exist_ok=True)
        for prefix in ("etc", "rom/etc"):
            (self.root / prefix / "openwrt_release").write_text("DISTRIB_RELEASE='25.12.6'\n")
            (self.root / prefix / "apk/repositories.d/distfeeds.list").write_text("https://downloads.openwrt.org/releases/25.12.6/packages/base/packages.adb\n")
        self.kernel = self.root / "kernel-version"
        self.kernel.write_text(ROM_KERNEL)
        self.state = self.root / "identity-state"
        self.state.write_bytes(b"fixture-existing-identity-and-preferences")
        self.before_state = self.state.read_bytes()
        self.script = self.root / "repo/Ensure-Tailscale.sh"
        self.script.write_text(self.rewrite((ROOT / "Ensure-Tailscale.sh").read_text()).replace("[ -c ", "[ -e "))
        self.script.chmod(0o755)
        self.command("id", "#!/bin/sh\nprintf '0\\n'\n")
        self.command("uname", "#!/bin/sh\nprintf '6.12.112\\n'\n")
        self.command("sleep", "#!/bin/sh\nexit 0\n")
        self.command("apk", f"#!{sys.executable}\n" + '''
import json, os, pathlib, sys
root = pathlib.Path(os.environ['TEST_ROOT'])
a = sys.argv[1:]
mirror = '--repositories-file' in a
lock_wait = '--wait' in a
while a and a[0] in ('--keys-dir', '--repositories-file', '--timeout', '--wait'):
    a = a[2:]
with (root / 'events').open('a') as stream:
    if mirror: stream.write(json.dumps(['mirror']) + '\\n')
    if lock_wait: stream.write(json.dumps(['apk-lock-wait']) + '\\n')
    stream.write(json.dumps(['apk', *a]) + '\\n')
if mirror and os.environ.get('TEST_MIRROR_SIGNATURE_FAIL') == 'true': sys.exit(1)
if 'query' in a:
    value = os.environ['TEST_ROM_KERNEL'] if '--root' in a else (root / 'kernel-version').read_text()
    print('# 1 items\\n- version: ' + value)
elif a[:2] == ['info', '-e']:
    sys.exit(0 if (root / 'packages-present').exists() else 1)
elif a == ['update']:
    failed = os.environ.get('TEST_UPDATE_FAIL') == 'true' or (os.environ.get('TEST_PRIMARY_FAIL') == 'true' and not mirror)
    sys.exit(1 if failed else 0)
elif a[:2] == ['add', '--simulate']:
    print(os.environ.get('TEST_PLAN', '(1/2) Installing tailscale (1.0)\\n(2/2) Installing kmod-tun (6.12.112-r1)'))
elif a == ['add', 'tailscale', 'kmod-tun']:
    (root / 'packages-present').touch()
    (root / 'modules/6.12.112/tun.ko').touch()
    binary = root / 'bin/tailscaled'
    binary.write_text('#!/bin/sh\\nexit 0\\n')
    binary.chmod(0o755)
else:
    sys.exit(90)
''')
        self.command("modprobe", f"#!{sys.executable}\n" + '''
import json, os, pathlib, sys
root = pathlib.Path(os.environ['TEST_ROOT'])
with (root / 'events').open('a') as stream: stream.write(json.dumps(['modprobe', *sys.argv[1:]]) + '\\n')
if os.environ.get('TEST_BAD_ABI') == 'true': sys.exit(1)
(root / 'tun').touch()
''')
        self.command("pidof", '#!/bin/sh\ntest -f "$TEST_ROOT/running"\n')
        self.command("tailscale", f"#!{sys.executable}\n" + '''
import json, os, pathlib, sys
root = pathlib.Path(os.environ['TEST_ROOT'])
with (root / 'events').open('a') as stream: stream.write(json.dumps(['tailscale', *sys.argv[1:]]) + '\\n')
if sys.argv[1:] != ['status', '--json']: sys.exit(91)
print(json.dumps({'BackendState': os.environ.get('TEST_BACKEND', 'Running'), 'Self': {'Online': os.environ.get('TEST_OFFLINE') != 'true'}}))
''')
        self.command("ubus", f"#!{sys.executable}\n" + '''
import json, os, pathlib
root = pathlib.Path(os.environ['TEST_ROOT'])
marker = root / 'argon-checked'
busy = os.environ.get('TEST_ARGON_BUSY') == 'true' or (os.environ.get('TEST_ARGON_ONCE') == 'true' and not marker.exists())
marker.touch()
with (root / 'events').open('a') as stream: stream.write(json.dumps(['argon-check', busy]) + '\\n')
print(json.dumps({'argon-auto-update': {'instances': {'job': {'running': busy}}}}))
''')
        self.command("jsonfilter", f"#!{sys.executable}\n" + '''
import json, sys
value = json.load(sys.stdin)
if 'argon-auto-update' in sys.argv[-1]:
    value = any(item.get('running') for item in value.get('argon-auto-update', {}).get('instances', {}).values())
else:
    for field in sys.argv[-1].removeprefix('@.').split('.'): value = value[field]
print(str(value).lower() if isinstance(value, bool) else value)
''')
        self.service = self.root / "etc/init.d/tailscale"
        self.service.write_text(f"#!{sys.executable}\n" + '''
import json, os, pathlib, sys
root = pathlib.Path(os.environ['TEST_ROOT'])
with (root / 'events').open('a') as stream: stream.write(json.dumps(['service', *sys.argv[1:]]) + '\\n')
if sys.argv[1:] == ['restart']: (root / 'running').touch()
''')
        self.service.chmod(0o755)

    def rewrite(self, text):
        pairs = [
            ("/rom/etc", self.root / "rom/etc"),
            ("/root/FirmwareUpgradeOpenWRT", self.root / "repo"),
            ("/rom", self.root / "rom"),
            ("/etc", self.root / "etc"),
            ("/dev/net/tun", self.root / "tun"),
            ("/lib/modules", self.root / "modules"),
            ("/var/lock", self.root / "lock"),
        ]
        for index, (old, _) in enumerate(pairs):
            text = text.replace(old, f"@@PATH{index}@@")
        for index, (_, new) in enumerate(pairs):
            text = text.replace(f"@@PATH{index}@@", str(new))
        return text

    def command(self, name, text):
        path = self.bin / name
        path.write_text(text)
        path.chmod(0o755)

    def invoke(self, *args):
        result = subprocess.run(["sh", str(self.script), *args], env=self.env, capture_output=True, text=True, timeout=5)
        self.assertEqual(self.state.read_bytes(), self.before_state)
        return result

    def recorded(self):
        return [json.loads(line) for line in self.events.read_text().splitlines()] if self.events.exists() else []

    def assert_no_mutations(self):
        self.assertTrue(all(event[0] == "apk" and "query" in event for event in self.recorded()), self.recorded())
        self.assertFalse((self.root / "lock/tailscale-auto-install.lock").exists())

    def test_check_only_is_read_only(self):
        self.assertEqual(self.invoke("--check").returncode, 0)
        self.assert_no_mutations()

    def test_mismatched_kernel_database_refuses_all_mutations(self):
        self.kernel.write_text("6.12.74~oldabi-r1")
        result = self.invoke("--non-interactive")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Kernel package metadata differs", result.stderr)
        self.assert_no_mutations()

    def test_running_kernel_must_match_rom(self):
        self.env["TEST_ROM_KERNEL"] = "6.12.999~wrong-r1"
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assert_no_mutations()

    def test_stale_release_metadata_is_refused(self):
        (self.root / "etc/openwrt_release").write_text("DISTRIB_RELEASE='24.10.4'\n")
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assert_no_mutations()

    def test_empty_release_metadata_is_not_treated_as_a_match(self):
        for prefix in ("etc", "rom/etc"):
            (self.root / prefix / "openwrt_release").write_text("# missing release field\n")
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assert_no_mutations()

    def test_stale_distribution_feeds_are_refused(self):
        (self.root / "etc/apk/repositories.d/distfeeds.list").write_text("old-feed\n")
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assert_no_mutations()

    def test_install_load_start_and_connection_check(self):
        result = self.invoke("--non-interactive")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["apk", "add", "tailscale", "kmod-tun"], self.recorded())
        self.assertIn(["modprobe", "tun"], self.recorded())
        self.assertIn(["service", "restart"], self.recorded())
        self.assertTrue((self.root / "tun").exists())
        self.assertFalse((self.root / "lock/tailscale-auto-install.lock").exists())

    def test_loaded_tun_device_does_not_hide_missing_module_for_next_boot(self):
        (self.root / "packages-present").touch()
        (self.root / "tun").touch()
        self.command("tailscaled", "#!/bin/sh\nexit 0\n")
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["apk", "add", "tailscale", "kmod-tun"], self.recorded())
        self.assertTrue((self.root / "modules/6.12.112/tun.ko").is_file())

    def test_second_run_does_not_reinstall_or_restart(self):
        self.assertEqual(self.invoke().returncode, 0)
        self.events.unlink()
        self.assertEqual(self.invoke().returncode, 0)
        self.assertFalse(any(event[:2] == ["apk", "add"] for event in self.recorded()))
        self.assertNotIn(["service", "restart"], self.recorded())

    def test_kernel_change_in_solver_plan_is_refused(self):
        self.env["TEST_PLAN"] = "(1/3) Downgrading kernel (6.12.112 -> 6.12.74)"
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assertNotIn(["apk", "add", "tailscale", "kmod-tun"], self.recorded())
        self.assertFalse(any(event[0] == "service" for event in self.recorded()))

    def test_failed_package_update_does_not_start_service(self):
        self.env["TEST_UPDATE_FAIL"] = "true"
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assertFalse(any(event[0] == "service" for event in self.recorded()))
        self.assertFalse((self.root / "lock/tailscale-auto-install.lock").exists())

    def test_https_mirror_restores_packages_without_changing_persistent_feeds(self):
        self.env["TEST_PRIMARY_FAIL"] = "true"
        feeds = self.root / "etc/apk/repositories.d/distfeeds.list"
        before = feeds.read_bytes()
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["mirror"], self.recorded())
        self.assertEqual(feeds.read_bytes(), before)
        self.assertEqual(list((self.root / "tmp").iterdir()), [])

    def test_mirror_signature_failure_never_starts_service(self):
        self.env.update(TEST_PRIMARY_FAIL="true", TEST_MIRROR_SIGNATURE_FAIL="true")
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assertFalse(any(event[0] == "service" for event in self.recorded()))
        self.assertEqual(list((self.root / "tmp").iterdir()), [])

    def test_kernel_plan_rejection_does_not_fall_back_to_mirror(self):
        self.env["TEST_PLAN"] = "(1/3) Downgrading kernel (6.12.112 -> 6.12.74)"
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assertNotIn(["mirror"], self.recorded())

    def test_argon_job_finishes_before_package_installation(self):
        self.env["TEST_ARGON_ONCE"] = "true"
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        events = self.recorded()
        self.assertIn(["argon-check", True], events)
        self.assertLess(events.index(["argon-check", False]), events.index(["apk", "update"]))
        self.assertIn(["apk-lock-wait"], events)

    def test_busy_argon_timeout_does_not_install_or_reset_anything(self):
        self.env["TEST_ARGON_BUSY"] = "true"
        self.script.write_text(self.script.read_text().replace('[ "$argon_wait" -lt 60 ]', '[ "$argon_wait" -lt 2 ]'))
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assertNotIn(["apk", "update"], self.recorded())
        self.assertFalse(any(event[0] == "service" for event in self.recorded()))
        self.assertFalse((self.root / "lock/tailscale-auto-install.lock").exists())

    def test_upgrade_script_does_not_restore_all_changed_etc_files(self):
        source = (ROOT / "Interactive-Firmware-Upgrade.sh").read_text()
        self.assertNotIn("sysupgrade -v -c", source)
        self.assertIn('sysupgrade -v "$FILENAME"', source)

    def test_rejected_module_does_not_start_service(self):
        self.env["TEST_BAD_ABI"] = "true"
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assertFalse(any(event[0] == "service" for event in self.recorded()))

    def test_login_is_never_reset_or_automatically_recreated(self):
        self.env["TEST_BACKEND"] = "NeedsLogin"
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assertTrue(all(event == ["tailscale", "status", "--json"] for event in self.recorded() if event[0] == "tailscale"))

    def test_existing_lock_is_not_removed(self):
        (self.root / "lock/tailscale-auto-install.lock").mkdir()
        self.assertEqual(self.invoke().returncode, 0)
        self.assertTrue((self.root / "lock/tailscale-auto-install.lock").exists())
        self.assertTrue(all("query" in event for event in self.recorded()))

    def test_setup_preservation_is_idempotent(self):
        setup = self.root / "repo/Install-Tailscale-Auto-Install.sh"
        setup.write_text(self.rewrite((ROOT / setup.name).read_text()))
        (self.root / "repo/Tailscale-Auto-Install.init").write_text('#!/bin/sh\nprintf "%s\\n" "$1" >> "$TEST_ROOT/bootstrap-actions"\n')
        conf = self.root / "etc/sysupgrade.conf"
        conf.write_text("# existing custom policy\n")
        for _ in range(2):
            result = subprocess.run(["sh", str(setup)], env=self.env, capture_output=True, text=True, timeout=3)
            self.assertEqual(result.returncode, 0, result.stderr)
        lines = conf.read_text().splitlines()
        self.assertEqual((self.root / "bootstrap-actions").read_text().splitlines(), ["enable", "start", "enable", "start"])
        self.assertEqual(len(lines), len(set(lines)))
        self.assertIn(str(self.root / "etc/tailscale"), lines)
        self.assertNotIn("/lib/apk/db", lines)
        self.assertNotIn("/lib/modules", lines)

    def test_setup_does_not_enable_or_change_preservation_on_bad_metadata(self):
        setup = self.root / "repo/Install-Tailscale-Auto-Install.sh"
        setup.write_text(self.rewrite((ROOT / setup.name).read_text()))
        (self.root / "repo/Tailscale-Auto-Install.init").write_text('#!/bin/sh\nexit 0\n')
        conf = self.root / "etc/sysupgrade.conf"
        conf.write_text("# existing custom policy\n")
        self.kernel.write_text("6.12.74~oldabi-r1")
        result = subprocess.run(["sh", str(setup)], env=self.env, capture_output=True, text=True, timeout=3)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(conf.read_text(), "# existing custom policy\n")
        self.assertFalse((self.root / "etc/init.d/tailscale-auto-install").exists())
        self.assert_no_mutations()

    def test_real_procd_service_wires_boot_and_both_wan_events(self):
        init = self.root / "repo/Tailscale-Auto-Install.init"
        init.write_text(self.rewrite((ROOT / init.name).read_text()))
        stub = '''
procd_open_instance() { :; }
procd_close_instance() { :; }
procd_set_param() { printf '%s\\n' "$*"; }
procd_add_interface_trigger() { printf '%s\\n' "$*"; }
'''
        result = subprocess.run(["sh", "-eu", "-c", stub + '\n. "$1"\nstart_service\nservice_triggers', "test", str(init)], capture_output=True, text=True, env=self.env, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(str(self.script) + " --non-interactive", result.stdout)
        self.assertIn("interface.up wan ", result.stdout)
        self.assertIn("interface.up wan6 ", result.stdout)
        self.assertNotIn("restart", result.stdout)
        self.assertNotIn("respawn", result.stdout)


if __name__ == "__main__":
    unittest.main()
