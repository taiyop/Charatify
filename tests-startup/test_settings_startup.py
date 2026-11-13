"""Bundle-level regression for the settings crash, without touching user data."""
import os
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
IDENTIFIERS = ("dev.local.CharacterNotification", "dev.local.CharacterNotification.dev")


class SettingsStartupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix="charatify-settings-build-")
        cls.addClassCleanup(cls.build.cleanup)
        build = Path(cls.build.name)
        objects = []
        # Compile the actual settings dependencies, without the GUI entry point
        # or Sparkle. Keep compiler artifacts inside the temporary directory.
        flags = ["-module-cache-path", str(build / "ModuleCache")]
        for module in ("AppConfiguration", "CharacterIconKit", "CharacterMediaKit"):
            obj = build / f"{module}.o"
            subprocess.run([
                "swiftc", *flags, "-parse-as-library", "-whole-module-optimization",
                "-emit-object", "-emit-module", "-module-name", module,
                "-emit-module-path", str(build / f"{module}.swiftmodule"),
                *map(str, sorted((ROOT / "Sources" / module).glob("*.swift"))),
                "-o", str(obj),
            ], check=True, cwd=ROOT)
            objects.append(str(obj))
        cls.executable = build / "SettingsStartupCheck"
        subprocess.run([
            "swiftc", *flags, "-parse-as-library", "-I", str(build),
            str(ROOT / "Sources/Charatify/Settings.swift"),
            str(ROOT / "tests-startup/SettingsStartupCheck.swift"),
            *objects, "-o", str(cls.executable),
        ], check=True, cwd=ROOT)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="charatify-settings-home-")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name).resolve()

    def launch(self, bundle_id, values, enabled, duration, display):
        contents = self.home / f"{bundle_id}.app/Contents"
        executable = contents / "MacOS/SettingsStartupCheck"
        executable.parent.mkdir(parents=True, exist_ok=True)
        if not executable.exists():
            executable.write_bytes(self.executable.read_bytes())
            executable.chmod(0o755)
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": bundle_id,
            "CFBundleExecutable": executable.name,
            "CFBundlePackageType": "APPL",
        }))
        fixture = self.home / "settings.plist"
        fixture.write_bytes(plistlib.dumps(values))
        result = subprocess.run([
            str(executable), bundle_id, str(fixture), str(enabled).lower(), str(duration), display, str(self.home),
        ], env=dict(os.environ, CFFIXED_USER_HOME=str(self.home)),
            capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"Settings startup passed: {bundle_id}", result.stdout)

    def test_startup_reads_settings_in_both_bundles(self):
        for bundle_id in IDENTIFIERS:
            with self.subTest(bundle_id=bundle_id):
                self.launch(bundle_id, {"enabled": False, "duration": 11, "displayID": "saved-display"},
                            False, 11, "saved-display")

    def test_startup_clamps_duration_and_tolerates_invalid_optional_data(self):
        for bundle_id in IDENTIFIERS:
            with self.subTest(bundle_id=bundle_id):
                self.launch(bundle_id, {"enabled": True, "duration": 999, "displayID": "main",
                                       "characterAppearance": b"invalid json", "iconConfiguration": b"invalid json"},
                            True, 30, "main")


if __name__ == "__main__":
    unittest.main()
