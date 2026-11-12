#!/usr/bin/env python3
"""Check release ordering, enclosure metadata, and the archive's Ed25519 signature."""
import base64
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def version_tuple(version):
    parts = version.split(".")
    if not 1 <= len(parts) <= 3 or not all(p.isascii() and p.isdigit() for p in parts):
        raise ValueError(f"Invalid release version: {version}")
    return tuple(int(p) for p in parts) + (0,) * (3 - len(parts))


def check_previous(path, version):
    new = version_tuple(version)
    root = ET.parse(path).getroot()
    if root.tag != "rss" or root.find("channel") is None:
        raise ValueError("Previous appcast is not an RSS update feed")
    for item in root.findall("./channel/item"):
        old = item.findtext(f"{{{SPARKLE}}}version")
        enclosure = item.find("enclosure")
        if old is None and enclosure is not None:
            old = enclosure.get(f"{{{SPARKLE}}}version")
        if old is None or version_tuple(old) >= new:
            raise ValueError("Release version must be greater than every published version")


def validate(path, archive, version, prefix):
    items = ET.parse(path).findall("./channel/item")
    matches = [i for i in items if i.findtext(f"{{{SPARKLE}}}version") == version]
    if len(matches) != 1:
        raise ValueError("Appcast must contain exactly one item for the new version")
    enclosure = matches[0].find("enclosure")
    if enclosure is None or enclosure.get("url") != prefix + archive.name:
        raise ValueError("Appcast download URL does not match this release")
    if enclosure.get("length") != str(archive.stat().st_size):
        raise ValueError("Appcast archive length does not match")
    signature = enclosure.get(f"{{{SPARKLE}}}edSignature", "")
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError("Appcast must contain an Ed25519 signature")
    return signature


if __name__ == "__main__":
    try:
        if sys.argv[1] == "--previous":
            check_previous(Path(sys.argv[2]), sys.argv[3])
        else:
            _, feed, archive, version, public_key, prefix = sys.argv
            signature = validate(Path(feed), Path(archive), version, prefix)
            subprocess.run(["swift", str(Path(__file__).with_name("verify-update.swift")),
                            archive, public_key, signature], check=True)
    except (ValueError, OSError, ET.ParseError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
