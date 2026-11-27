from datetime import date
import importlib.util
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import json
import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import release_version


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


metadata = load("configure-update")
publisher = load("publish-release")


class ReleasePublicationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.version = "0.3.2"
        self.tag = self.version
        self.configure_assets()

    def configure_assets(self, notarized=False):
        suffix = "" if notarized else "-unnotarized"
        self.assets = [self.directory / name for name in [
            f"Charatify-{self.version}{suffix}.dmg",
            f"Charatify-{self.version}-macos-universal{suffix}.zip",
            "SHA256SUMS",
        ]]
        for asset in self.assets:
            asset.write_bytes(b"asset")

    def publish(self, notarized=False):
        return publisher.publish("taiyop/Charatify", self.tag, self.version, self.directory,
                                 notarized=notarized, target="commit-sha")

    def release(self, draft=False, prerelease=False, assets=None):
        return {"tag_name": self.tag, "draft": draft, "prerelease": prerelease,
                "assets": [{"name": asset.name, "state": "uploaded"} for asset in
                           (self.assets if assets is None else assets)]}

    def test_unnotarized_stable_publishes_after_all_update_assets_upload(self):
        with patch.object(publisher, "gh", side_effect=["[[]]", "", "", ""]) as gh:
            url = self.publish()
        calls = [call.args for call in gh.call_args_list]
        self.assertIn("--draft", calls[1])
        self.assertIn("--verify-tag", calls[1])
        self.assertNotIn("--prerelease", calls[1])
        self.assertIn(f"[Download {self.assets[0].name}]({url})", calls[1][-2])
        self.assertEqual(calls[2], ("release", "upload", self.tag, *map(str, self.assets), "--clobber"))
        self.assertEqual(calls[3], ("release", "edit", self.tag, "--draft=false", "--latest"))

    def test_nightly_is_a_prerelease_on_the_requested_commit(self):
        self.version = self.tag = "0.3.2-nightly.20261127.2"
        self.configure_assets(notarized=True)
        with patch.object(publisher, "gh", side_effect=["[[]]", "", "", ""]) as gh:
            self.publish(notarized=True)
        calls = [call.args for call in gh.call_args_list]
        self.assertIn("--prerelease", calls[1])
        self.assertIn("commit-sha", calls[1])
        self.assertIn("--latest=false", calls[3])
        self.assertNotIn("notarized", calls[1][-2])

    def test_existing_complete_release_is_preserved_on_retry(self):
        pages = [[], [self.release()]]
        with patch.object(publisher, "gh", return_value=json.dumps(pages)) as gh:
            self.publish()
        self.assertEqual(gh.call_count, 1)

    def test_retry_uploads_zip_and_checksum_together_on_a_partial_draft(self):
        pages = [[self.release(draft=True, assets=self.assets[:2])]]
        with patch.object(publisher, "gh", side_effect=[json.dumps(pages), "", ""]) as gh:
            self.publish()
        self.assertEqual(gh.call_args_list[1].args, ("release", "upload", self.tag, *map(str, self.assets), "--clobber"))
        self.assertEqual(gh.call_args.args[:3], ("release", "edit", self.tag))

    def test_published_incomplete_release_is_never_modified(self):
        for existing in (self.release(assets=self.assets[:1]), self.release(prerelease=True)):
            with patch.object(publisher, "gh", return_value=json.dumps([[existing]])) as gh:
                with self.assertRaises(ValueError):
                    self.publish()
                self.assertEqual(gh.call_count, 1)

    def test_upload_failure_leaves_release_unpublished(self):
        with patch.object(publisher, "gh", side_effect=["[[]]", "", subprocess.CalledProcessError(1, "gh")]) as gh:
            with self.assertRaises(subprocess.CalledProcessError):
                self.publish()
        self.assertEqual(gh.call_count, 3)

    def test_missing_local_checksum_fails_before_contacting_github(self):
        self.assets[-1].unlink()
        with patch.object(publisher, "gh") as gh:
            with self.assertRaises(ValueError):
                self.publish()
        gh.assert_not_called()


class ReleaseMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.info = Path(self.temp.name) / "Info.plist"
        self.info.write_bytes((ROOT / "Resources/Info.plist").read_bytes())

    def configure(self, **env):
        metadata.configure(self.info, env)
        return plistlib.loads(self.info.read_bytes())

    def test_release_keeps_identity_and_sets_its_update_signing_requirement(self):
        for adhoc in ("0", "1"):
            with self.subTest(adhoc=adhoc):
                info = self.configure(APP_VARIANT="release", DMG_ONLY=adhoc, APP_VERSION="0.3.2")
                self.assertEqual(info["CFBundleIdentifier"], "dev.local.CharacterNotification")
                self.assertEqual(info["CFBundleVersion"], "0.3.2")
                self.assertEqual(info["CharatifyUpdateRequiresDeveloperID"], adhoc == "0")
                self.assertNotIn("SUFeedURL", info)
                self.assertNotIn("SUPublicEDKey", info)

    def test_dev_identity_is_separate(self):
        info = self.configure(APP_VARIANT="dev", DMG_ONLY="0")
        self.assertEqual(info["CFBundleIdentifier"], "dev.local.CharacterNotification.dev")
        self.assertEqual(info["CFBundleDisplayName"], "Charatify Dev")
        self.assertFalse(info["CharatifyUpdateRequiresDeveloperID"])

    def test_nightly_keeps_numeric_bundle_versions_and_clears_the_label_on_stable(self):
        label = "0.3.2-nightly.20261127.2"
        with self.assertRaises(ValueError):
            self.configure(APP_VARIANT="release", DMG_ONLY="1", APP_VERSION=label)
        info = self.configure(APP_VARIANT="release", DMG_ONLY="1", APP_VERSION=label, APP_BUILD_VERSION="1.0.2")
        self.assertEqual(info["CFBundleShortVersionString"], "0.3.2")
        self.assertEqual(info["CFBundleVersion"], "1.0.2")
        self.assertEqual(info["CharatifyNightlyVersion"], label)
        info = self.configure(APP_VARIANT="release", APP_VERSION="0.3.2")
        self.assertNotIn("CharatifyNightlyVersion", info)

    def test_invalid_plist_inputs_leave_source_unchanged(self):
        before = self.info.read_bytes()
        for env in [{"APP_VARIANT": "production"}, {"DMG_ONLY": "yes"}, {"APP_VERSION": "0.3.2-beta"}]:
            with self.subTest(env=env), self.assertRaises(ValueError):
                metadata.configure(self.info, env)
            self.assertEqual(self.info.read_bytes(), before)

    def test_release_script_refuses_missing_notarization_or_ad_hoc_signing(self):
        env = {"PATH": os.environ["PATH"], "APP_VERSION": "0.3.2",
               "CODE_SIGN_IDENTITY": "Developer ID Application: Test (TEAM)"}
        command = ["zsh", str(ROOT / "scripts/release.sh")]
        missing = subprocess.run(command, env=env, capture_output=True, text=True)
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("Release requires notarization", missing.stderr)
        env.update(APPLE_ID="test@example.com", APPLE_TEAM_ID="TEAM", APPLE_APP_SPECIFIC_PASSWORD="unused",
                   CODE_SIGN_IDENTITY="-")
        invalid = subprocess.run(command, env=env, capture_output=True, text=True)
        self.assertNotEqual(invalid.returncode, 0)
        self.assertIn("Developer ID Application", invalid.stderr)


class StableVersionTests(unittest.TestCase):
    def test_bumps_highest_numeric_stable_tag(self):
        tags = ["0.9.99", "v0.10.9", "v1.0.0-nightly.20261127.24", "v2.0.0-rc.1"]
        for bump, expected in [("major", "1.0.0"), ("minor", "0.11.0"), ("patch", "0.10.10")]:
            with self.subTest(bump=bump):
                self.assertEqual(release_version.next_stable_version(tags, "0.1.0", bump), expected)

    def test_uses_bundle_version_when_there_are_no_stable_tags(self):
        self.assertEqual(release_version.next_stable_version(["v2.0.0-rc.1"], "0.1.0", "patch"), "0.1.1")

    def test_tag_command_can_preview_or_tag_head(self):
        with tempfile.TemporaryDirectory() as directory:
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=directory, text=True).strip()

            git("init", "-q")
            git("config", "tag.gpgSign", "false")
            git("-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgSign=false",
                "commit", "--allow-empty", "-qm", "First commit")
            git("tag", "v0.1.2")
            command = [sys.executable, str(ROOT / "scripts/release_version.py"), "tag", "patch"]
            self.assertEqual(subprocess.check_output([*command, "--dry-run"], cwd=directory, text=True).strip(),
                             "0.1.3")
            self.assertEqual(git("tag"), "v0.1.2")
            self.assertEqual(subprocess.check_output(command, cwd=directory, text=True).strip(), "0.1.3")
            self.assertEqual(git("tag"), "0.1.3\nv0.1.2")
            self.assertEqual(git("rev-parse", "0.1.3^{commit}"), git("rev-parse", "HEAD"))


class NightlyVersionTests(unittest.TestCase):
    def test_uses_next_patch_and_ignores_older_tags_and_prereleases(self):
        day = date(2026, 11, 27)
        tags = ["0.9.5", "v0.10.9", "v0.10.10-nightly.20261126.23"]
        version = release_version.nightly_tag(tags, [], "0.1.0", day, 24, True)
        self.assertEqual(version, "0.10.10-nightly.20261127.24")

    def test_scheduled_runs_skip_existing_builds_and_reruns_reuse_the_release_tag(self):
        previous = "0.10.10-nightly.20261126.23"
        day = date(2026, 11, 27)
        pick = release_version.nightly_tag
        for tag in (previous, f"v{previous}"):
            with self.subTest(tag=tag):
                tags = ["v0.10.10", tag]
                self.assertIsNone(pick(tags, [tag], "0.1.0", day, 24, True))
                self.assertEqual(pick(tags, [tag], "0.1.0", day, 23, True), tag)
                self.assertEqual(pick(tags, [tag], "0.1.0", day, 24, False), "0.10.11-nightly.20261127.24")

    def test_build_numbers_are_monotonic_across_component_rollovers(self):
        builds = [release_version.version_tuple(release_version.ci_build_version(run))
                  for run in (1, 99, 100, 9999, 10000, 10001)]
        self.assertEqual(builds, sorted(set(builds)))
        self.assertGreater(builds[0], (0, 2, 1))


if __name__ == "__main__":
    unittest.main()
