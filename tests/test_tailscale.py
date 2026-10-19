"""Exercise Tailscale restoration against disposable OpenWrt fixtures."""

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
        self.temporary = tempfile.TemporaryDirectory(prefix="tailscale-restore-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.events = self.root / "events"
        self.identity = self.root / "etc/tailscale/tailscaled.state"
        self.env = os.environ.copy()
        self.env.update(PATH=f"{self.bin}{os.pathsep}{self.env['PATH']}", TEST_ROOT=str(self.root))
        for path in (
            "etc/apk/repositories.d", "rom/etc/apk/repositories.d", "rom/etc/apk/keys",
            "etc/init.d", "etc/tailscale", "lock", "modules/6.12.112", "repo",
        ):
            (self.root / path).mkdir(parents=True, exist_ok=True)
        for prefix in ("etc", "rom/etc"):
            (self.root / prefix / "openwrt_release").write_text("DISTRIB_RELEASE='25.12.6'\n")
            (self.root / prefix / "apk/repositories.d/distfeeds.list").write_text("fixture feed\n")
        (self.root / "kernel-version").write_text(ROM_KERNEL)
        self.identity.write_bytes(b"existing identity and preferences")
        self.original_identity = self.identity.read_bytes()
        self.script = self.root / "repo/Ensure-Tailscale.sh"
        self.script.write_text(self.rewrite((ROOT / "Ensure-Tailscale.sh").read_text()).replace("[ -c ", "[ -e "))
        self.script.chmod(0o755)

        self.command("id", "#!/bin/sh\nprintf '0\\n'\n")
        self.command("uname", f"#!{sys.executable}\nimport os\nprint(os.environ.get('TEST_RUNNING_KERNEL', '6.12.112'))\n")
        self.command("sleep", "#!/bin/sh\nexit 0\n")
        self.command("apk", f"#!{sys.executable}\n" + r'''
import json, os, pathlib, sys
root = pathlib.Path(os.environ["TEST_ROOT"])
a = sys.argv[1:]
with (root / "events").open("a") as stream:
    stream.write(json.dumps(["apk", *a]) + "\n")
command = next((word for word in ("query", "info", "update", "add") if word in a), None)
if command == "query":
    print("# 1 items\n- version: " + (os.environ.get("TEST_ROM_KERNEL", "6.12.112~testabi-r1") if "--root" in a else (root / "kernel-version").read_text()))
elif command == "info":
    package = a[a.index("-e") + 1]
    sys.exit(0 if (root / f"{package}-present").exists() else 1)
elif command == "update":
    pass
elif command == "add":
    requested = a[a.index("add") + 1:]
    requested = [item for item in requested if not item.startswith("-")]
    versions = {
        "tailscale": "1.80.3-r1",
        "kmod-tun": "6.12.112-r1",
        "luci-app-tailscale-community": "26.288.56989~75a306d",
    }
    plan = os.environ.get("TEST_PLAN")
    if plan is None:
        plan = "\n".join(f"({index:3d}/{len(requested)}) Installing {package} ({versions[package]})" for index, package in enumerate(requested, 1))
    print(plan)
    if "--simulate" not in a:
        for package in requested:
            (root / f"{package}-present").touch()
        if "kmod-tun" in requested:
            (root / "modules/6.12.112/tun.ko").touch()
        if "tailscale" in requested:
            daemon = root / "bin/tailscaled"
            daemon.write_text("#!/bin/sh\nexit 0\n")
            daemon.chmod(0o755)
else:
    sys.exit(90)
''')
        self.command("modprobe", f"#!{sys.executable}\n" + r'''
import json, os, pathlib, sys
root = pathlib.Path(os.environ["TEST_ROOT"])
with (root / "events").open("a") as stream: stream.write(json.dumps(["modprobe", *sys.argv[1:]]) + "\n")
(root / "tun").touch()
''')
        self.command("pidof", '#!/bin/sh\ntest -f "$TEST_ROOT/running"\n')
        self.command("tailscale", f"#!{sys.executable}\n" + r'''
import json, os, pathlib, sys
root = pathlib.Path(os.environ["TEST_ROOT"])
with (root / "events").open("a") as stream: stream.write(json.dumps(["tailscale", *sys.argv[1:]]) + "\n")
if sys.argv[1:] != ["status", "--json"]: sys.exit(91)
print(json.dumps({"BackendState": os.environ.get("TEST_BACKEND", "Running"), "Self": {"Online": True}}))
''')
        self.command("jsonfilter", f"#!{sys.executable}\n" + r'''
import json, sys
value = json.load(sys.stdin)
for field in sys.argv[-1].removeprefix("@.").split("."): value = value[field]
print(str(value).lower() if isinstance(value, bool) else value)
''')
        service = self.root / "etc/init.d/tailscale"
        service.write_text(f"#!{sys.executable}\n" + r'''
import json, os, pathlib, sys
root = pathlib.Path(os.environ["TEST_ROOT"])
with (root / "events").open("a") as stream: stream.write(json.dumps(["service", *sys.argv[1:]]) + "\n")
if sys.argv[1:] == ["restart"]: (root / "running").touch()
''')
        service.chmod(0o755)

    def rewrite(self, text):
        pairs = [
            ("/rom/etc", self.root / "rom/etc"), ("/rom", self.root / "rom"),
            ("/etc", self.root / "etc"), ("/dev/net/tun", self.root / "tun"),
            ("/lib/modules", self.root / "modules"), ("/var/lock", self.root / "lock"),
            ("/root/FirmwareUpgradeOpenWRT", self.root / "repo"),
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

    def invoke(self, *arguments):
        result = subprocess.run(
            ["sh", str(self.script), *arguments], env=self.env,
            capture_output=True, text=True, timeout=5,
        )
        self.assertEqual(self.identity.read_bytes(), self.original_identity)
        return result

    def recorded(self):
        return [json.loads(line) for line in self.events.read_text().splitlines()] if self.events.exists() else []

    def adds(self):
        return [event for event in self.recorded() if event[0] == "apk" and "add" in event]

    def mark_present(self, package):
        (self.root / f"{package}-present").touch()
        if package == "tailscale":
            self.command("tailscaled", "#!/bin/sh\nexit 0\n")
        elif package == "kmod-tun":
            (self.root / "modules/6.12.112/tun.ko").touch()

    def test_metadata_guard_is_read_only_and_refuses_mismatches(self):
        result = self.invoke("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(all(event[0] == "apk" and "query" in event for event in self.recorded()))

        cases = (
            ("installed kernel", lambda: (self.root / "kernel-version").write_text("6.12.74~old-r1")),
            ("running kernel", lambda: self.env.__setitem__("TEST_RUNNING_KERNEL", "6.12.74")),
            ("release", lambda: (self.root / "etc/openwrt_release").write_text("DISTRIB_RELEASE='24.10.4'\n")),
            ("feeds", lambda: (self.root / "etc/apk/repositories.d/distfeeds.list").write_text("stale feed\n")),
        )
        for name, break_metadata in cases:
            with self.subTest(name=name):
                (self.root / "kernel-version").write_text(ROM_KERNEL)
                self.env.pop("TEST_RUNNING_KERNEL", None)
                (self.root / "etc/openwrt_release").write_text("DISTRIB_RELEASE='25.12.6'\n")
                (self.root / "etc/apk/repositories.d/distfeeds.list").write_text("fixture feed\n")
                self.events.unlink(missing_ok=True)
                break_metadata()
                self.assertNotEqual(self.invoke().returncode, 0)
                self.assertFalse(any("update" in event or "add" in event for event in self.recorded()))

    def test_existing_packages_are_untouched_and_second_run_is_idempotent(self):
        self.mark_present("tailscale")
        self.mark_present("kmod-tun")
        self.mark_present("luci-app-tailscale-community")
        (self.root / "running").touch()
        for _ in range(2):
            result = self.invoke()
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.adds())
        self.assertNotIn(["service", "restart"], self.recorded())

    def test_only_missing_package_is_simulated_then_added(self):
        self.mark_present("tailscale")
        self.mark_present("luci-app-tailscale-community")
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        adds = self.adds()
        self.assertEqual(len(adds), 2)
        self.assertIn("--simulate", adds[0])
        self.assertNotIn("--simulate", adds[1])
        for event in adds:
            requested = [item for item in event[event.index("add") + 1:] if not item.startswith("-")]
            self.assertEqual(requested, ["kmod-tun"])

    def test_only_missing_luci_app_is_simulated_then_added(self):
        self.mark_present("tailscale")
        self.mark_present("kmod-tun")
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        for event in self.adds():
            requested = [item for item in event[event.index("add") + 1:] if not item.startswith("-")]
            self.assertEqual(requested, ["luci-app-tailscale-community"])

    def test_any_non_installing_simulated_action_is_refused(self):
        for action in ("Upgrading", "Downgrading", "Reinstalling", "Purging"):
            with self.subTest(action=action):
                self.events.unlink(missing_ok=True)
                self.env["TEST_PLAN"] = f"(  1/2) Installing tailscale (1.80.3-r1)\n(  2/2) {action} kernel (old -> new)"
                result = self.invoke()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len(self.adds()), 1)
                self.assertIn("--simulate", self.adds()[0])

    def test_shared_lock_is_used_and_an_existing_owner_is_preserved(self):
        lock_name = "/var/lock/post-sysupgrade-package-install.lock"
        self.assertIn(lock_name, (ROOT / "Ensure-Tailscale.sh").read_text())
        self.assertIn(lock_name, (ROOT / "Install-LuCI-Argon-Theme.sh").read_text())
        lock = self.root / "lock/post-sysupgrade-package-install.lock"
        lock.mkdir()
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(lock.exists())
        self.assertFalse(any("info" in event or "add" in event for event in self.recorded()))

    def test_identity_is_retained_and_login_is_never_created_or_reset(self):
        self.mark_present("tailscale")
        self.mark_present("kmod-tun")
        self.mark_present("luci-app-tailscale-community")
        self.env["TEST_BACKEND"] = "NeedsLogin"
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        calls = [event for event in self.recorded() if event[0] == "tailscale"]
        self.assertTrue(calls)
        self.assertTrue(all(event == ["tailscale", "status", "--json"] for event in calls))
        self.assertIn("no login or reset", result.stderr)

    def test_procd_uses_start_for_boot_and_network_triggers(self):
        init = self.root / "repo/Tailscale-Auto-Install.init"
        init.write_text(self.rewrite((ROOT / init.name).read_text()))
        stub = '''
procd_open_instance() { :; }
procd_close_instance() { :; }
procd_set_param() { printf '%s\n' "$*"; }
procd_add_interface_trigger() { printf '%s\n' "$*"; }
'''
        result = subprocess.run(
            ["sh", "-eu", "-c", stub + '\n. "$1"\nstart_service\nservice_triggers', "test", str(init)],
            env=self.env, capture_output=True, text=True, timeout=3,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("interface.up lan ", result.stdout)
        self.assertIn("interface.up wan ", result.stdout)
        self.assertIn("interface.up wan6 ", result.stdout)
        self.assertNotIn("restart", result.stdout)
        self.assertNotIn("respawn", result.stdout)


if __name__ == "__main__":
    unittest.main()
