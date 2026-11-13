#!/usr/bin/env python3
"""Attach a DMG-only tag build to a GitHub prerelease."""

import json
import os
from pathlib import Path
import subprocess


def gh(*args):
    return subprocess.run(["gh", *args], check=True, stdout=subprocess.PIPE, text=True).stdout


def publish(repository, tag, version, archive):
    if not archive.is_file():
        raise ValueError(f"DMG not found: {archive}")
    pages = json.loads(gh("api", "--paginate", "--slurp",
                          f"repos/{repository}/releases?per_page=100"))
    release = next((release for page in pages for release in page
                    if release["tag_name"] == tag), None)
    if release is not None and not release["prerelease"]:
        raise ValueError("Refusing to modify a stable release with an unnotarized DMG")

    download_url = f"https://github.com/{repository}/releases/download/{tag}/{archive.name}"
    if release is None:
        notes = (f"[Download {archive.name}]({download_url})\n\n"
                 "This app uses ad-hoc signing and is not notarized. "
                 "macOS may block opening it. Update checking is disabled.")
        gh("release", "create", tag, "--draft", "--prerelease", "--verify-tag",
           "--latest=false", "--title", f"Charatify {version} (unnotarized)", "--notes", notes)
    # Keep an already uploaded asset on retries, including immutable releases.
    if release is None or not any(asset["name"] == archive.name for asset in release["assets"]):
        gh("release", "upload", tag, str(archive))
    if release is None or release["draft"]:
        gh("release", "edit", tag, "--draft=false", "--latest=false")
    return download_url


if __name__ == "__main__":
    version = os.environ["APP_VERSION"]
    url = publish(os.environ["GITHUB_REPOSITORY"], os.environ["RELEASE_TAG"], version,
                  Path(f"build/dmg/Charatify-{version}-unnotarized.dmg"))
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
        summary.write(f"\n[Download DMG]({url}) (unnotarized; update checking disabled).\n")
