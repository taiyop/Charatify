#!/usr/bin/env python3
"""Validate release inputs before writing them into the built app's Info.plist."""
import base64
import os
import plistlib
import re
import sys
from pathlib import Path
from urllib.parse import urlparse


def configure(path, env):
    with path.open("rb") as source:
        info = plistlib.load(source)
    variant = env.get("APP_VARIANT", "dev")
    if variant not in ("dev", "release"):
        raise ValueError("APP_VARIANT must be dev or release")
    version = env.get("APP_VERSION", info["CFBundleShortVersionString"])
    build = env.get("APP_BUILD_VERSION", version)
    for name, value in [("APP_VERSION", version), ("APP_BUILD_VERSION", build)]:
        if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value):
            raise ValueError(f"{name} must be a numeric version (e.g. 0.2.0)")
    info.update(CFBundleShortVersionString=version, CFBundleVersion=build)
    if variant == "dev":
        info.update(CFBundleIdentifier="dev.local.CharacterNotification.dev",
                    CFBundleName="Charatify Dev", CFBundleDisplayName="Charatify Dev",
                    CFBundleIconFile="CharatifyDev", SUEnableAutomaticChecks=False)
        # Do not let an inherited release environment turn a Dev app into an updater.
        info.pop("SUFeedURL", None)
        info.pop("SUPublicEDKey", None)
    else:
        feed = env.get("SPARKLE_FEED_URL", info.get("SUFeedURL", ""))
        parsed = urlparse(feed)
        if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
            raise ValueError("SPARKLE_FEED_URL must be an HTTPS URL without credentials")
        key = env.get("SPARKLE_PUBLIC_ED_KEY", info.get("SUPublicEDKey", "")).strip()
        try:
            if len(base64.b64decode(key, validate=True)) != 32:
                raise ValueError()
        except ValueError:
            raise ValueError("SPARKLE_PUBLIC_ED_KEY must be a base64 encoded 32-byte Ed25519 public key") from None
        info.update(CFBundleIdentifier="dev.local.CharacterNotification",
                    CFBundleName="Charatify", CFBundleDisplayName="Charatify",
                    SUFeedURL=feed, SUPublicEDKey=key, SUEnableAutomaticChecks=True)
    with path.open("wb") as target:
        plistlib.dump(info, target, sort_keys=False)


if __name__ == "__main__":
    try:
        configure(Path(sys.argv[1]), os.environ)
    except (ValueError, OSError) as error:
        sys.exit(str(error))
