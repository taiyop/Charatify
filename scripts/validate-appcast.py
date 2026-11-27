#!/usr/bin/env python3
"""Check release ordering, enclosure metadata, and the archive's Ed25519 signature."""
import argparse
import base64
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from release_version import release_version, version_tuple

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
NS = {"sparkle": SPARKLE}
ET.register_namespace("sparkle", SPARKLE)


def read_feed(path):
    root = ET.parse(path).getroot()
    channel = root.find("channel")
    if root.tag != "rss" or channel is None:
        raise ValueError("Appcast is not an RSS update feed")
    return root, channel


def item_version(item, key):
    value = item.findtext(f"sparkle:{key}", namespaces=NS)
    enclosure = item.find("enclosure")
    if value is None and enclosure is not None:
        value = enclosure.get(f"{{{SPARKLE}}}{key}")
    return value


def check_previous_items(items, build, version):
    new_build = version_tuple(build)
    base, channel = release_version(version)
    for item in items:
        old_build = item_version(item, "version")
        if old_build is None or version_tuple(old_build) >= new_build:
            raise ValueError("Build number must be greater than every published build")
        if channel is None and item.findtext("sparkle:channel", namespaces=NS) is None:
            short = item_version(item, "shortVersionString") or old_build
            if version_tuple(short) >= version_tuple(base):
                raise ValueError("Stable version must be greater than every published stable version")


def check_previous(path, build, version):
    _, channel = read_feed(path)
    check_previous_items(channel.findall("item"), build, version)


def release_item(feed, build, version, check_label=True):
    matches = [item for item in feed.findall("item") if item_version(item, "version") == build]
    if len(matches) != 1:
        raise ValueError("Appcast must contain exactly one item for the build")
    item = matches[0]
    _, channel = release_version(version)
    if item.findtext("sparkle:channel", namespaces=NS) != channel:
        raise ValueError("Appcast update channel does not match this release")
    if check_label and (item_version(item, "shortVersionString") or build) != version:
        raise ValueError("Appcast display version does not match this release")
    return item


def write_feed(root, path):
    ET.indent(root)
    ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)


def set_nightly_label(path, build, version):
    root, feed = read_feed(path)
    item = release_item(feed, build, version, check_label=False)
    label = item.find("sparkle:shortVersionString", NS)
    if label is None:
        label = ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString")
    label.text = version
    title = item.find("title")
    if title is not None:
        title.text = version
    write_feed(root, path)


def validate(path, archive, build, prefix, version):
    _, feed = read_feed(path)
    enclosure = release_item(feed, build, version).find("enclosure")
    if enclosure is None or enclosure.get("url") != prefix + archive.name:
        raise ValueError("Appcast download URL does not match this release")
    if enclosure.get("length") != str(archive.stat().st_size):
        raise ValueError("Appcast archive length does not match")
    signature = enclosure.get(f"{{{SPARKLE}}}edSignature", "")
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError("Appcast must contain an Ed25519 signature")
    return signature


def merge(path, candidate, build, version):
    candidate_root, candidate_feed = read_feed(candidate)
    item = release_item(candidate_feed, build, version)
    if not path.exists():
        for other in candidate_feed.findall("item"):
            if other is not item:
                candidate_feed.remove(other)
        write_feed(candidate_root, path)
        return

    root, feed = read_feed(path)
    items = feed.findall("item")
    if any(item_version(existing, "version") == build for existing in items):
        existing = release_item(feed, build, version)
        if existing.find("enclosure").attrib != item.find("enclosure").attrib:
            raise ValueError("Published appcast entry differs from this release")
        return

    check_previous_items(items, build, version)
    if items:
        feed.insert(list(feed).index(items[0]), item)
    else:
        feed.append(item)
    # Keep Sparkle's usual three releases per channel for each macOS minimum.
    branch = tuple(item.findtext(key, namespaces=NS) for key in
                   ("sparkle:channel", "sparkle:minimumSystemVersion"))
    same_branch = [existing for existing in items if
                   tuple(existing.findtext(key, namespaces=NS) for key in
                         ("sparkle:channel", "sparkle:minimumSystemVersion")) == branch]
    for old in same_branch[2:]:
        feed.remove(old)
    write_feed(root, path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("check-previous", "set-nightly-label", "validate", "merge"):
        command = commands.add_parser(name)
        command.add_argument("feed", type=Path)
        command.add_argument("build")
        command.add_argument("version")
        if name == "validate":
            command.add_argument("--archive", type=Path, required=True)
            command.add_argument("--download-prefix", required=True)
            command.add_argument("--public-key", required=True)
        if name == "merge":
            command.add_argument("--candidate", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "check-previous":
            check_previous(args.feed, args.build, args.version)
        elif args.command == "set-nightly-label":
            set_nightly_label(args.feed, args.build, args.version)
        elif args.command == "merge":
            merge(args.feed, args.candidate, args.build, args.version)
        else:
            signature = validate(args.feed, args.archive, args.build, args.download_prefix, args.version)
            subprocess.run(["swift", str(Path(__file__).with_name("verify-update.swift")),
                            args.archive, args.public_key, signature], check=True)
    except (ValueError, OSError, ET.ParseError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
