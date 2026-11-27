#!/usr/bin/env python3
"""Validate release inputs before writing them into the built app's Info.plist."""
import os
import plistlib
import sys
from pathlib import Path

from release_version import release_version, version_tuple


def configure(path, env):
    with path.open("rb") as source:
        info = plistlib.load(source)
    variant = env.get("APP_VARIANT", "dev")
    if variant not in ("dev", "release"):
        raise ValueError("APP_VARIANT must be dev or release")
    dmg_only = env.get("DMG_ONLY", "0")
    if dmg_only not in ("0", "1"):
        raise ValueError("DMG_ONLY must be 0 or 1")
    version = env.get("APP_VERSION", info["CFBundleShortVersionString"])
    base, channel = release_version(version)
    build = env.get("APP_BUILD_VERSION")
    if channel == "nightly" and build is None:
        raise ValueError("Nightly releases require a numeric APP_BUILD_VERSION")
    build = base if build is None else build
    version_tuple(build)
    info.update(CFBundleShortVersionString=base, CFBundleVersion=build)
    if channel == "nightly":
        info["CharatifyNightlyVersion"] = version
    else:
        info.pop("CharatifyNightlyVersion", None)
    if variant == "dev":
        info.update(CFBundleIdentifier="dev.local.CharacterNotification.dev",
                    CFBundleName="Charatify Dev", CFBundleDisplayName="Charatify Dev",
                    CFBundleIconFile="CharatifyDev")
    else:
        info.update(CFBundleIdentifier="dev.local.CharacterNotification",
                    CFBundleName="Charatify", CFBundleDisplayName="Charatify")
    info["CharatifyUpdateRequiresDeveloperID"] = variant == "release" and dmg_only == "0"
    with path.open("wb") as target:
        plistlib.dump(info, target, sort_keys=False)


if __name__ == "__main__":
    try:
        configure(Path(sys.argv[1]), os.environ)
    except (ValueError, OSError) as error:
        sys.exit(str(error))
