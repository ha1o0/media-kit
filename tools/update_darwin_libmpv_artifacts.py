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
FRAMEWORK = r"[A-Za-z0-9_-]+"
TARGETS = r"^let libmpvTargets = \[(?s:.*?)^\]"
CHECKSUMS = r"^let libmpvChecksums = \[(?s:.*?)^\]"


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


def swift_pins(text, name):
    blocks = []
    for pattern in (TARGETS, CHECKSUMS):
        matches = list(re.finditer(pattern, text, re.MULTILINE))
        if len(matches) != 1:
            raise ValueError(f"Unexpected SwiftPM pin block for {name}")
        blocks.append(matches[0].group())
    names = re.findall(rf'"({FRAMEWORK})"', blocks[0])
    entries = re.findall(rf'^([ \t]*)"({FRAMEWORK})": "([a-f0-9]{{64}})"',
                         blocks[1], re.MULTILINE)
    keys = [framework for _, framework, _ in entries]
    if (not names or "Mpv" not in names or len(set(names)) != len(names) or
            not keys or "Mpv" not in keys or len(set(keys)) != len(keys)):
        raise ValueError(f"Unexpected SwiftPM framework list for {name}")
    return blocks, names, entries


def released_frameworks(assets, stem, required, name):
    pattern = re.compile(rf"{re.escape(stem)}_({FRAMEWORK})\.zip")
    frameworks = {}
    for asset in assets:
        if not asset.startswith(stem + "_") or not asset.endswith(".zip"):
            continue
        match = pattern.fullmatch(asset)
        if not match:
            raise ValueError(f"Unexpected framework asset: {asset}")
        frameworks[match[1]] = checksum(assets, asset)
    if ("Mpv" not in frameworks or
            not set(required).issubset(frameworks)):
        missing = set(required) - frameworks.keys()
        raise ValueError(f"Missing uploaded SwiftPM frameworks for {name}: {sorted(missing)}")
    if len({framework.lower() for framework in frameworks}) != len(frameworks):
        raise ValueError(f"Conflicting framework asset names for {name}")
    return {framework: frameworks[framework] for framework in sorted(frameworks)}


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
        blocks, targets, entries = swift_pins(old_swift, name)
        required = set(targets) | {framework for _, framework, _ in entries}
        frameworks = released_frameworks(assets, stem, required, name)
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
        same_version = f"MPV_XCFRAMEWORKS_VERSION={tag}" in old_make.splitlines()
        if make_text != old_make and same_version:
            raise ValueError(f"{name}: same version changed origin or checksum; use a new immutable tag")
        swift_text = replace_once(r'^let libmpvArtifactBase = "[^"\r\n]+"', old_swift,
                                  f'let libmpvArtifactBase = "{release_base}/{tag}/{stem}"')
        old_checksums = {framework: sha for _, framework, sha in entries}
        if same_version and (set(targets) != frameworks.keys() or
                             old_checksums != frameworks or swift_text != old_swift):
            raise ValueError(f"{name}: same version changed SwiftPM assets; use a new immutable tag")
        if set(targets) == frameworks.keys() and old_checksums.keys() == frameworks.keys():
            checksums = blocks[1]
            for indent, framework, _ in entries:
                checksums = replace_once(rf'^[ \t]*"{re.escape(framework)}": "[a-f0-9]{{64}}"',
                                          checksums, f'{indent}"{framework}": "{frameworks[framework]}"')
            swift_text = replace_once(CHECKSUMS, swift_text, checksums)
        else:
            target_list = "let libmpvTargets = [\n" + ",\n".join(
                f'    "{framework}"' for framework in frameworks) + "\n]"
            checksum_list = "let libmpvChecksums = [\n" + ",\n".join(
                f'    "{framework}": "{sha}"' for framework, sha in frameworks.items()) + "\n]"
            swift_text = replace_once(TARGETS, swift_text, target_list)
            swift_text = replace_once(CHECKSUMS, swift_text, checksum_list)
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
