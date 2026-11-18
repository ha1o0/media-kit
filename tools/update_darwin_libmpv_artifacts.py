#!/usr/bin/env python3
"""Update exactly one Apple platform's libmpv pins from a GitHub release."""

import argparse
from pathlib import Path
import re
import sys
from urllib.error import URLError
from urllib.parse import quote
from urllib.request import Request, urlopen
import json


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_REPO = "ha1o0/libmpv-darwin-build"
TAG = re.compile(r"v[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*)?")
REPO = re.compile(r"[A-Za-z0-9_-]+/[A-Za-z0-9_-]+")
DIGEST = re.compile(r"sha256:([a-f0-9]{64})")


def validate_selection(platform, tag, repo):
    if platform not in ("ios", "macos"):
        raise ValueError("Select exactly one platform: ios or macos")
    if not tag or not TAG.fullmatch(tag) or len(tag) > 100:
        raise ValueError("Specify a release version such as v2.26.1 or v2.27.0-ios.1")
    if not REPO.fullmatch(repo):
        raise ValueError("Repository must be owner/name")
    typed = re.search(r"-(ios|macos)\.", tag)
    if typed and typed[1] != platform:
        raise ValueError(f"Tag {tag} is for {typed[1]}, not {platform}")


def release_metadata(repo, tag):
    request = Request(
        f"https://api.github.com/repos/{repo}/releases/tags/{quote(tag, safe='')}",
        headers={"Accept": "application/vnd.github+json", "User-Agent": "media-kit-darwin-libmpv"},
    )
    with urlopen(request, timeout=30) as response:
        return json.load(response)


def release_assets(release, tag):
    if release.get("tag_name") != tag or release.get("draft") is not False:
        raise ValueError("Release must be published and match the requested tag")
    assets = {}
    for asset in release["assets"]:
        name = asset["name"]
        if name in assets:
            raise ValueError(f"Duplicate release asset: {name}")
        assets[name] = asset
    return assets


def checksum(assets, name):
    asset = assets.get(name, {})
    digest = DIGEST.fullmatch(asset.get("digest") or "")
    if asset.get("state") != "uploaded" or not digest:
        raise ValueError(f"Missing uploaded asset with SHA-256: {name}")
    return digest[1]


def replace_once(pattern, text, replacement):
    if len(list(re.finditer(pattern, text, re.MULTILINE))) != 1:
        raise ValueError(f"Unexpected pin format: {pattern}")
    return re.sub(pattern, lambda _: replacement, text, count=1, flags=re.MULTILINE)


def package_dir(root, platform, variant):
    package = f"media_kit_libs_{platform}_{variant}"
    return root / "libs" / platform / package / platform, package


def plan(root, platform, variant, tag, repo, mode, release):
    validate_selection(platform, tag, repo)
    assets = release_assets(release, tag)
    changes = {}
    for item in ("audio", "video") if variant == "all" else (variant,):
        flavor = "full" if mode == "full" or (platform, item) == ("macos", "audio") else "default"
        stem = f"libmpv-xcframeworks_{tag}_{platform}-universal-{item}-{flavor}"
        archive_checksum = checksum(assets, f"{stem}.tar.gz")
        package, name = package_dir(root, platform, item)
        make = package / "Makefile"
        swift = package / name / "Package.swift"
        old_make, old_swift = (path.read_bytes().decode() for path in (make, swift))
        make_text = replace_once(r"^MPV_XCFRAMEWORKS_VERSION=[^\r\n]+", old_make,
                                 f"MPV_XCFRAMEWORKS_VERSION={tag}")
        make_text = replace_once(r"^MPV_XCFRAMEWORKS_SHA256SUM=[^\r\n]+", make_text,
                                 f"MPV_XCFRAMEWORKS_SHA256SUM={archive_checksum}")
        variable = "${MPV_XCFRAMEWORKS_VERSION}"
        release_base = f"https://github.com/{repo}/releases/download"
        make_url = f"{release_base}/{variable}/{stem.replace(tag, variable, 1)}.tar.gz"
        make_text = replace_once(
            rf"https://github\.com/[^\s/]+/[^\s/]+/releases/download/[^\s]+_{platform}-universal-{item}-[^\s]+\.tar\.gz",
            make_text, make_url,
        )
        if make_text != old_make and f"MPV_XCFRAMEWORKS_VERSION={tag}" in old_make.splitlines():
            raise ValueError(f"{name}: same version changed origin or checksum; use a new immutable tag")
        swift_text = replace_once(r'^let libmpvArtifactBase = "[^"\r\n]+"', old_swift,
                                  f'let libmpvArtifactBase = "{release_base}/{tag}/{stem}"')
        entries = re.findall(r'^([ \t]*)"([A-Za-z0-9-]+)": "[a-f0-9]{64}"', old_swift, re.MULTILINE)
        names = [framework for _, framework in entries]
        if not names or len(set(names)) != len(names) or "Mpv" not in names:
            raise ValueError(f"Unexpected SwiftPM framework list for {name}")
        for indent, framework in entries:
            sha = checksum(assets, f"{stem}_{framework}.zip")
            swift_text = replace_once(rf'^[ \t]*"{re.escape(framework)}": "[a-f0-9]{{64}}"',
                                      swift_text, f'{indent}"{framework}": "{sha}"')
        for path, before, after in ((make, old_make, make_text), (swift, old_swift, swift_text)):
            if before != after:
                changes[path] = (before.encode(), after.encode())
    return changes


def apply(changes):
    for path, (before, _) in changes.items():
        if path.read_bytes() != before:
            raise ValueError(f"Pin changed while preparing the update: {path}")
    written = []
    try:
        for path, (_, after) in changes.items():
            written.append(path)
            path.write_bytes(after)
    except OSError:
        for path in reversed(written):
            path.write_bytes(changes[path][0])
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--platform", required=True, choices=("ios", "macos"))
    parser.add_argument("--version", help="Published release tag")
    parser.add_argument("legacy_version", nargs="?", help=argparse.SUPPRESS)
    parser.add_argument("--repo", default=DEFAULT_REPO)
    parser.add_argument("--variant", default="video", choices=("video", "audio", "all"))
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--mode", choices=("full", "default"), default="full", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if bool(args.version) == bool(args.legacy_version):
        parser.error("specify exactly one version using --version TAG")
    tag = args.version or args.legacy_version
    try:
        validate_selection(args.platform, tag, args.repo)
        changes = plan(ROOT, args.platform, args.variant, tag, args.repo, args.mode,
                       release_metadata(args.repo, tag))
        if not args.dry_run:
            apply(changes)
        print(f"{args.platform}/{args.variant}: {args.repo}@{tag}")
        for path in changes:
            print(f"{'Would update' if args.dry_run else 'Updated'} {path.relative_to(ROOT)}")
        if not changes:
            print("Pins already match this release.")
    except (ValueError, OSError, URLError, KeyError) as exc:
        sys.exit(str(exc))


if __name__ == "__main__":
    main()
