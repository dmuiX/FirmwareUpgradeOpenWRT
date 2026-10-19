"""Exercise Argon restoration against disposable OpenWrt fixtures."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
ROM_KERNEL = "6.12.112~testabi-r1"


class ArgonRestoreTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="argon-restore-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.events = self.root / "events"
        self.env = os.environ.copy()
        self.env.update(PATH=f"{self.bin}{os.pathsep}{self.env['PATH']}", TEST_ROOT=str(self.root))
        for path in (
            "etc/apk/repositories.d", "rom/etc/apk/repositories.d", "etc/init.d",
            "lock", "tmp", "www/luci-static",
        ):
            (self.root / path).mkdir(parents=True, exist_ok=True)
        for prefix in ("etc", "rom/etc"):
            (self.root / prefix / "openwrt_release").write_text("DISTRIB_RELEASE='25.12.6'\n")
            (self.root / prefix / "apk/repositories.d/distfeeds.list").write_text("fixture feed\n")
        (self.root / "kernel-version").write_text(ROM_KERNEL)
        package_bytes = b"pinned argon package"
        package_hash = hashlib.sha256(package_bytes).hexdigest()
        self.script = self.root / "Install-LuCI-Argon-Theme.sh"
        source = self.rewrite((ROOT / self.script.name).read_text())
        source = source.replace("d21fe8574183e4d78b6347431b5e0a4e48666453435b5d07d2ca44de2b491654", package_hash)
        self.script.write_text(source)
        self.script.chmod(0o755)

        self.command("id", "#!/bin/sh\nprintf '0\\n'\n")
        self.command("uname", "#!/bin/sh\nprintf '6.12.112\\n'\n")
        self.command("sleep", "#!/bin/sh\nexit 0\n")
        self.command("wget", f"#!{sys.executable}\n" + r'''
import json, os, pathlib, sys
root = pathlib.Path(os.environ["TEST_ROOT"])
with (root / "events").open("a") as stream: stream.write(json.dumps(["wget", *sys.argv[1:]]) + "\n")
if "-t" in sys.argv: sys.exit(92)
out = pathlib.Path(sys.argv[sys.argv.index("-O") + 1])
out.write_bytes(b"bad" if os.environ.get("TEST_BAD_HASH") else b"pinned argon package")
''')
        self.command("apk", f"#!{sys.executable}\n" + r'''
import json, os, pathlib, sys
root = pathlib.Path(os.environ["TEST_ROOT"])
a = sys.argv[1:]
with (root / "events").open("a") as stream: stream.write(json.dumps(["apk", *a]) + "\n")
command = next((word for word in ("query", "info", "add") if word in a), None)
if command == "query":
    print("# 1 items\n- version: " + ("6.12.112~testabi-r1" if "--root" in a else (root / "kernel-version").read_text()))
elif command == "info":
    sys.exit(0 if (root / "argon-present").exists() else 1)
elif command == "add":
    print(os.environ.get("TEST_PLAN", "(  1/1) Installing luci-theme-argon (3.0.0-r2)"))
    if "--simulate" not in a:
        (root / "argon-present").touch()
        (root / "www/luci-static/argon").mkdir(exist_ok=True)
else:
    sys.exit(90)
''')
        self.command("uci", f"#!{sys.executable}\n" + r'''
import json, os, pathlib, sys
root = pathlib.Path(os.environ["TEST_ROOT"])
with (root / "events").open("a") as stream: stream.write(json.dumps(["uci", *sys.argv[1:]]) + "\n")
if sys.argv[1:] == ["get", "luci.main.mediaurlbase"]:
    if (root / "argon-active").exists(): print("/luci-static/argon")
    else: sys.exit(1)
elif sys.argv[1:] == ["set", "luci.main.mediaurlbase=/luci-static/argon"]:
    (root / "argon-active").touch()
''')
        service = self.root / "etc/init.d/uhttpd"
        service.write_text("#!/bin/sh\nexit 0\n")
        service.chmod(0o755)

    def rewrite(self, text):
        pairs = [
            ("/rom/etc", self.root / "rom/etc"), ("/rom", self.root / "rom"),
            ("/etc", self.root / "etc"), ("/www", self.root / "www"),
            ("/var/lock", self.root / "lock"), ("/tmp", self.root / "tmp"),
            ("/root/FirmwareUpgradeOpenWRT", self.root),
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
        return subprocess.run(
            ["sh", str(self.script), *arguments], env=self.env,
            capture_output=True, text=True, timeout=5,
        )

    def recorded(self):
        return [json.loads(line) for line in self.events.read_text().splitlines()] if self.events.exists() else []

    def adds(self):
        return [event for event in self.recorded() if event[0] == "apk" and "add" in event]

    def test_coherent_check_is_read_only_and_empty_release_is_refused(self):
        result = self.invoke("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(all(event[0] == "apk" and "query" in event for event in self.recorded()))
        self.events.unlink()
        for prefix in ("etc", "rom/etc"):
            (self.root / prefix / "openwrt_release").write_text("# no release\n")
        result = self.invoke("--check")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Release metadata is empty", result.stderr)

    def test_existing_package_is_untouched_and_activation_is_idempotent(self):
        (self.root / "argon-present").touch()
        (self.root / "www/luci-static/argon").mkdir()
        for _ in range(2):
            result = self.invoke()
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(event[0] == "wget" for event in self.recorded()))
        self.assertFalse(self.adds())
        self.assertTrue((self.root / "argon-active").exists())

    def test_missing_package_replaces_unowned_theme_files_and_activates(self):
        # A settings-preserving sysupgrade can restore these files without APK metadata.
        (self.root / "www/luci-static/argon").mkdir()
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.adds()), 2)
        self.assertIn("--simulate", self.adds()[0])
        self.assertNotIn("--simulate", self.adds()[1])
        self.assertEqual(self.adds()[0][-1], self.adds()[1][-1])
        self.assertTrue((self.root / "argon-active").exists())

    def test_any_non_installing_simulated_action_is_refused(self):
        for action in ("Upgrading", "Downgrading", "Reinstalling", "Purging"):
            with self.subTest(action=action):
                self.events.unlink(missing_ok=True)
                self.env["TEST_PLAN"] = f"(  1/1) {action} luci-theme-argon (3.0.0-r2)"
                result = self.invoke()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len(self.adds()), 1)
                self.assertIn("--simulate", self.adds()[0])

    def test_checksum_mismatch_is_refused_before_apk_add(self):
        self.env["TEST_BAD_HASH"] = "true"
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("checksum mismatch", result.stderr)
        self.assertFalse(self.adds())

    def test_shared_lock_prevents_download_and_preserves_its_owner(self):
        lock = self.root / "lock/post-sysupgrade-package-install.lock"
        lock.mkdir()
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(lock.exists())
        self.assertFalse(any(event[0] == "wget" for event in self.recorded()))

    def test_procd_uses_start_for_boot_and_network_triggers(self):
        init = self.root / "Argon-Auto-Update.init"
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
