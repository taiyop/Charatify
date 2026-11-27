#!/usr/bin/env python3
"""Publish a DMG and its matching in-app update assets on GitHub Releases."""

import json
import os
from pathlib import Path
import subprocess

from release_version import release_version


def gh(*args):
    return subprocess.run(["gh", *args], check=True, stdout=subprocess.PIPE, text=True).stdout


def publish(repository, tag, version, directory, *, notarized, target):
    _, channel = release_version(version)
    nightly = channel == "nightly"
    suffix = "" if notarized else "-unnotarized"
    dmg = f"Charatify-{version}{suffix}.dmg"
    archive = f"Charatify-{version}-macos-universal{suffix}.zip"
    assets = [directory / name for name in (dmg, archive, "SHA256SUMS")]
    for path in assets:
        if not path.is_file():
            raise ValueError(f"Release asset not found: {path}")

    download_url = f"https://github.com/{repository}/releases/download/{tag}/{dmg}"
    pages = json.loads(gh("api", "--paginate", "--slurp", f"repos/{repository}/releases?per_page=100"))
    release = next((release for page in pages for release in page if release["tag_name"] == tag), None)
    if release is not None:
        if release["prerelease"] != nightly:
            raise ValueError(f"Release channel does not match the existing release for {tag}")
        if not release["draft"]:
            uploaded = {asset["name"] for asset in release["assets"] if asset["state"] == "uploaded"}
            if {path.name for path in assets} <= uploaded:
                return download_url
            raise ValueError(f"Published release {tag} has different or missing assets. Use a new tag.")

    if release is None:
        notes = f"[Download {dmg}]({download_url})\n\n"
        title = f"Charatify {version}"
        if not notarized:
            notes += "This build uses ad-hoc signing and is not notarized. macOS may block opening it.\n\n"
            title += " (unnotarized)"
        channel_flags = ("--prerelease", "--target", target) if nightly else ("--verify-tag",)
        gh("release", "create", tag, "--draft", "--latest=false", *channel_flags,
           "--title", title, "--notes", notes, "--generate-notes")

    # Build retries can produce different bytes. Upload the complete set on the draft
    # so the ZIP and checksum always come from the same build.
    gh("release", "upload", tag, *(str(path) for path in assets), "--clobber")
    gh("release", "edit", tag, "--draft=false", "--latest=false" if nightly else "--latest")
    return download_url


if __name__ == "__main__":
    url = publish(os.environ["GITHUB_REPOSITORY"], os.environ["RELEASE_TAG"], os.environ["APP_VERSION"],
                  Path(os.environ["PACKAGE_DIR"]), notarized=os.environ["NOTARIZE_RELEASE"] == "1",
                  target=os.environ["GITHUB_SHA"])
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
        summary.write(f"\n[Download DMG]({url})\n")
