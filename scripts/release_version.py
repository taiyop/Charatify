"""Version names and numeric bundle build identifiers for releases."""
import argparse
from datetime import date
import plistlib
import re
import subprocess
from pathlib import Path


STABLE_TAG = re.compile(r"v?([0-9]+\.[0-9]+\.[0-9]+)")
NIGHTLY_VERSION = re.compile(r"([0-9]+\.[0-9]+\.[0-9]+)-nightly\.([0-9]{8})\.([1-9][0-9]*)")
STABLE_BUMPS = ("major", "minor", "patch")


def version_tuple(version):
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", version):
        raise ValueError(f"Invalid release version: {version}")
    parts = tuple(map(int, version.split(".")))
    return parts + (0,) * (3 - len(parts))


def release_version(version):
    match = NIGHTLY_VERSION.fullmatch(version)
    if match:
        date.fromisoformat(f"{match[2][:4]}-{match[2][4:6]}-{match[2][6:]}")
        return match[1], "nightly"
    version_tuple(version)
    return version, None


def ci_build_version(run_number):
    # Both channels use the same sequence, ahead of the existing 0.x.y builds.
    return f"{1 + run_number // 10000}.{run_number // 100 % 100}.{run_number % 100}"


def next_stable_version(tags, fallback, bump):
    stable_versions = [version_tuple(match[1]) for tag in tags if (match := STABLE_TAG.fullmatch(tag))]
    major, minor, patch = max(stable_versions, default=version_tuple(fallback))
    return {
        "major": f"{major + 1}.0.0",
        "minor": f"{major}.{minor + 1}.0",
        "patch": f"{major}.{minor}.{patch + 1}",
    }[bump]


def nightly_tag(tags, head_tags, fallback, build_date, run_number, require_new_commit):
    # Published tags make reruns deterministic even if a newer stable tag has appeared.
    head_nightlies = [(tag, match) for tag in head_tags
                      if (match := NIGHTLY_VERSION.fullmatch(tag.removeprefix("v")))]
    for tag, match in head_nightlies:
        if int(match[3]) == run_number:
            return tag
    if require_new_commit and head_nightlies:
        return None
    base = next_stable_version(tags, fallback, "patch")
    return f"{base}-nightly.{build_date:%Y%m%d}.{run_number}"


def git_tags(*args):
    return subprocess.check_output(["git", "tag", *args], text=True).splitlines()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)
    build = subcommands.add_parser("build")
    build.add_argument("run_number", type=int)
    tag = subcommands.add_parser("tag", help="Create the next stable tag at HEAD")
    tag.add_argument("bump", choices=STABLE_BUMPS)
    tag.add_argument("--dry-run", action="store_true", help="Print the tag without creating it")
    nightly = subcommands.add_parser("nightly", help="Choose a Nightly release tag")
    nightly.add_argument("run_number", type=int)
    nightly.add_argument("date", type=date.fromisoformat)
    nightly.add_argument("--require-new-commit", action="store_true")
    args = parser.parse_args()
    if args.command == "build":
        print(ci_build_version(args.run_number))
        return

    info = Path(__file__).resolve().parents[1] / "Resources/Info.plist"
    fallback = plistlib.loads(info.read_bytes())["CFBundleShortVersionString"]
    if args.command == "tag":
        next_tag = next_stable_version(git_tags(), fallback, args.bump)
        if not args.dry_run:
            subprocess.run(["git", "tag", next_tag], check=True)
        print(next_tag)
        return

    next_tag = nightly_tag(git_tags("--merged", "HEAD"), git_tags("--points-at", "HEAD"),
                           fallback, args.date, args.run_number, args.require_new_commit)
    if next_tag is not None:
        print(next_tag)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
