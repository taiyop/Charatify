import base64
import importlib.util
import plistlib
import tempfile
import unittest
import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


metadata = load("configure-update")
appcast = load("validate-appcast")


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.info = self.path / "Info.plist"
        self.info.write_bytes((ROOT / "Resources/Info.plist").read_bytes())
        self.key = base64.b64encode(bytes(range(32))).decode()

    def test_release_requires_key_and_accepts_valid_configuration(self):
        with self.assertRaises(ValueError):
            metadata.configure(self.info, {"APP_VARIANT": "release"})
        metadata.configure(self.info, {"APP_VARIANT": "release", "SPARKLE_PUBLIC_ED_KEY": self.key,
                                       "APP_VERSION": "0.2.0", "APP_BUILD_VERSION": "42"})
        info = plistlib.loads(self.info.read_bytes())
        self.assertEqual(info["CFBundleVersion"], "42")
        self.assertEqual(info["CFBundleShortVersionString"], "0.2.0")
        self.assertEqual(info["SUPublicEDKey"], self.key)
        self.assertEqual(info["CFBundleIdentifier"], "dev.local.CharacterNotification")

    def test_dev_identity_is_separate_and_cannot_inherit_release_updater_settings(self):
        metadata.configure(self.info, {"SPARKLE_PUBLIC_ED_KEY": self.key,
                                       "SPARKLE_FEED_URL": "https://example.com/production.xml"})
        info = plistlib.loads(self.info.read_bytes())
        self.assertEqual(info["CFBundleIdentifier"], "dev.local.CharacterNotification.dev")
        self.assertEqual(info["CFBundleDisplayName"], "Charatify Dev")
        self.assertEqual(info["CFBundleIconFile"], "CharatifyDev")
        self.assertNotIn("SUFeedURL", info)
        self.assertNotIn("SUPublicEDKey", info)
        self.assertFalse(info["SUEnableAutomaticChecks"])

    def test_unknown_variant_is_rejected(self):
        with self.assertRaises(ValueError):
            metadata.configure(self.info, {"APP_VARIANT": "production"})

    def test_dmg_only_uses_release_identity_without_update_keys(self):
        for update_env in [{}, {"SPARKLE_PUBLIC_ED_KEY": self.key,
                               "SPARKLE_FEED_URL": "https://example.com/production.xml"}]:
            with self.subTest(update_env=update_env):
                self.info.write_bytes((ROOT / "Resources/Info.plist").read_bytes())
                metadata.configure(self.info, dict(update_env, APP_VARIANT="release", DMG_ONLY="1",
                                                   APP_VERSION="0.1.0"))
                info = plistlib.loads(self.info.read_bytes())
                self.assertEqual(info["CFBundleIdentifier"], "dev.local.CharacterNotification")
                self.assertEqual(info["CFBundleDisplayName"], "Charatify")
                self.assertEqual(info["CFBundleVersion"], "0.1.0")
                self.assertNotIn("SUFeedURL", info)
                self.assertNotIn("SUPublicEDKey", info)
                self.assertFalse(info["SUEnableAutomaticChecks"])

    def test_invalid_dmg_only_mode_is_rejected_without_writing(self):
        before = self.info.read_bytes()
        with self.assertRaises(ValueError):
            metadata.configure(self.info, {"DMG_ONLY": "yes"})
        self.assertEqual(self.info.read_bytes(), before)
        env = {"PATH": os.environ["PATH"], "APP_VERSION": "0.1.0", "DMG_ONLY": "yes"}
        result = subprocess.run(["zsh", str(ROOT / "scripts/release.sh")], env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("DMG_ONLY must be 0 or 1", result.stderr)

    def test_release_script_refuses_missing_notarization_or_ad_hoc_signing(self):
        env = {"PATH": os.environ["PATH"], "APP_VERSION": "0.2.0", "SPARKLE_PUBLIC_ED_KEY": self.key,
               "RELEASE_DOWNLOAD_URL": "https://example.com/releases/",
               "CODE_SIGN_IDENTITY": "Developer ID Application: Test (TEAM)"}
        missing = subprocess.run(["zsh", str(ROOT / "scripts/release.sh")], env=env, capture_output=True, text=True)
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("Release requires notarization", missing.stderr)
        env.update(APPLE_ID="test@example.com", APPLE_TEAM_ID="TEAM", APPLE_APP_SPECIFIC_PASSWORD="unused",
                   CODE_SIGN_IDENTITY="-")
        invalid = subprocess.run(["zsh", str(ROOT / "scripts/release.sh")], env=env, capture_output=True, text=True)
        self.assertNotEqual(invalid.returncode, 0)
        self.assertIn("Developer ID Application", invalid.stderr)

    def test_invalid_release_inputs_do_not_modify_plist(self):
        before = self.info.read_bytes()
        for env in [{"SPARKLE_PUBLIC_ED_KEY": "placeholder"},
                    {"SPARKLE_PUBLIC_ED_KEY": base64.b64encode(b"short").decode()},
                    {"SPARKLE_FEED_URL": "http://example.com/appcast.xml"},
                    {"SPARKLE_FEED_URL": "https://user:password@example.com/appcast.xml"},
                    {"APP_VERSION": "0.2.0-beta"}]:
            with self.subTest(env=env), self.assertRaises(ValueError):
                metadata.configure(self.info, dict(env, APP_VARIANT="release", SPARKLE_PUBLIC_ED_KEY=env.get("SPARKLE_PUBLIC_ED_KEY", self.key)))
            self.assertEqual(self.info.read_bytes(), before)

    def feed(self, version="0.2.0", size="7", signature=None, url=None):
        signature = signature or base64.b64encode(bytes(64)).decode()
        url = url or "https://example.com/v0.2.0/Charatify-0.2.0.dmg"
        path = self.path / "appcast.xml"
        path.write_text(f'''<rss xmlns:sparkle="{appcast.SPARKLE}"><channel><item>
          <sparkle:version>{version}</sparkle:version>
          <enclosure url="{url}" length="{size}" sparkle:edSignature="{signature}"/>
          </item></channel></rss>''')
        return path

    def test_version_ordering_uses_numbers_and_rejects_repeats(self):
        feed = self.feed("0.9.0")
        appcast.check_previous(feed, "0.10.0")
        for version in ["0.9.0", "0.9", "0.8.9"]:
            with self.subTest(version=version), self.assertRaises(ValueError):
                appcast.check_previous(feed, version)

    def test_archive_metadata_must_match(self):
        archive = self.path / "Charatify-0.2.0.dmg"
        archive.write_bytes(b"archive")
        prefix = "https://example.com/v0.2.0/"
        appcast.validate(self.feed(), archive, "0.2.0", prefix)
        for params in [{"size": "8"}, {"signature": "invalid"},
                       {"url": "https://example.com/other.dmg"}, {"version": "0.1.0"}]:
            with self.subTest(params=params), self.assertRaises(ValueError):
                appcast.validate(self.feed(**params), archive, "0.2.0", prefix)

    def test_invalid_previous_feed_is_not_treated_as_an_empty_history(self):
        feed = self.path / "appcast.xml"
        feed.write_text("<html><body>Not found</body></html>")
        with self.assertRaises(ValueError):
            appcast.check_previous(feed, "0.2.0")


if __name__ == "__main__":
    unittest.main()
