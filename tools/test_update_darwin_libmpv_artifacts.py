import copy
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import update_darwin_libmpv_artifacts as updater


VIDEO_18 = [
    "Ass", "Avcodec", "Avfilter", "Avformat", "Avutil", "Dav1d", "Freetype",
    "Fribidi", "Harfbuzz", "Mbedcrypto", "Mbedtls", "Mbedx509", "Mpv", "Png16",
    "Swresample", "Swscale", "Uchardet", "Xml2",
]
VIDEO_29 = sorted(VIDEO_18 + [
    "Dovi", "Glslang", "Glslang-default-resource-limits", "Lcms2", "MoltenVK",
    "Placebo", "SPIRV", "SPIRV-Tools-shared", "SPVRemapper", "Shaderc_shared", "Vulkan",
])


class DarwinUpdaterTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for platform in ("ios", "macos"):
            for variant in ("audio", "video"):
                source, name = updater.package_dir(updater.ROOT, platform, variant)
                dest, _ = updater.package_dir(self.root, platform, variant)
                (dest / name).mkdir(parents=True)
                shutil.copyfile(source / "Makefile", dest / "Makefile")
                shutil.copyfile(source / name / "Package.swift", dest / name / "Package.swift")

    def release(self, platform, tag, variants=("video",), mode="full"):
        assets = []
        for variant in variants:
            flavor = "full" if mode == "full" or (platform, variant) == ("macos", "audio") else "default"
            stem = f"libmpv-xcframeworks_{tag}_{platform}-universal-{variant}-{flavor}"
            package, name = updater.package_dir(self.root, platform, variant)
            swift = (package / name / "Package.swift").read_text()
            keys = re.findall(r'^\s*"([A-Za-z0-9_-]+)": "[a-f0-9]{64}"', swift, re.M)
            names = [f"{stem}.tar.gz", *(f"{stem}_{key}.zip" for key in keys)]
            assets.extend({"name": name, "digest": "sha256:" + "5" * 64,
                           "state": "uploaded"} for name in names)
        return {"tag_name": tag, "draft": False, "assets": assets}

    def inventory_release(self, platform, tag, frameworks, variant="video"):
        # The release inventory is independent of the existing Swift table.
        stem = f"libmpv-xcframeworks_{tag}_{platform}-universal-{variant}-full"
        names = [f"{stem}.tar.gz", *(f"{stem}_{framework}.zip" for framework in frameworks)]
        return {"tag_name": tag, "draft": False,
                "assets": [{"name": name, "digest": "sha256:" + f"{index + 1:064x}",
                            "state": "uploaded"} for index, name in enumerate(names)]}

    def legacy_video_fixture(self):
        package, name = updater.package_dir(self.root, "macos", "video")
        swift = package / name / "Package.swift"
        before = swift.read_text()
        before = re.sub(r'^let libmpvTargets = \[(?s:.*?)^\]',
                        "let libmpvTargets = [\n" + ",\n".join(f'    "{item}"' for item in VIDEO_18) + "\n]",
                        before, count=1, flags=re.M)
        before = re.sub(r'^let libmpvChecksums = \[(?s:.*?)^\]',
                        "let libmpvChecksums = [\n" + ",\n".join(f'    "{item}": "' + "1" * 64 + '"' for item in VIDEO_18) + "\n]",
                        before, count=1, flags=re.M)
        swift.write_text(before)
        return package / "Makefile", swift

    def snapshot(self):
        return {p.relative_to(self.root): p.read_bytes()
                for p in self.root.rglob("*") if p.is_file()}

    def test_updates_one_platform_only_even_with_a_legacy_release_containing_both(self):
        tag = "v10.0.0"
        release = self.release("macos", tag, ("audio", "video"))
        release["assets"] += self.release("ios", tag)["assets"]
        for platform, variant in (("macos", "all"), ("ios", "video")):
            with self.subTest(platform=platform):
                before = self.snapshot()
                plan = updater.plan(self.root, platform, variant, tag, updater.DEFAULT_REPO, "full", release)
                self.assertEqual(len(plan), 4 if variant == "all" else 2)
                self.assertEqual(before, self.snapshot())  # preview doesn't write
                updater.apply(plan)
                after = self.snapshot()
                self.assertEqual(before.keys(), after.keys())
                self.assertEqual({p for p in before if before[p] != after[p]},
                                 {p.relative_to(self.root) for p in plan})
                self.assertTrue(all(p.relative_to(self.root).parts[:2] == ("libs", platform) for p in plan))
                self.assertEqual(updater.plan(self.root, platform, variant, tag,
                                              updater.DEFAULT_REPO, "full", release), {})

    def test_bad_or_missing_asset_never_writes_audio_or_video_pins(self):
        tag = "v10.0.0-macos.1"
        fixture = self.release("macos", tag, ("audio", "video"))
        before = self.snapshot()
        for key in ("missing", "digest", "wrong-tag"):
            release = copy.deepcopy(fixture)
            if key == "missing":
                release["assets"].pop()
            elif key == "digest":
                release["assets"][-1]["digest"] = "sha256:invalid"
            else:
                release["tag_name"] = "v10.0.0-macos.2"
            with self.subTest(key=key), self.assertRaises(ValueError):
                updater.plan(self.root, "macos", "all", tag, updater.DEFAULT_REPO, "full", release)
            self.assertEqual(self.snapshot(), before)

    def test_positional_tag_without_platform_and_cross_platform_tags_are_rejected(self):
        for tool in ("update_darwin_libmpv_artifacts.sh", "update_darwin_libmpv_artifacts_full.sh"):
            result = subprocess.run(["bash", str(updater.ROOT / "tools" / tool), "v2.26.1"],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("--platform", result.stderr)
        with self.assertRaisesRegex(ValueError, "not macos"):
            updater.validate_selection("macos", "v10.0.0-ios.1", updater.DEFAULT_REPO)

    def test_repo_switch_rewrites_both_downloaders_only_with_a_new_tag(self):
        tag = "v10.0.0-ios.1"
        release = self.release("ios", tag)
        plan = updater.plan(self.root, "ios", "video", tag, "ha1o0/libmpv-ios-build", "full", release)
        self.assertTrue(all(b"ha1o0/libmpv-ios-build/releases/download/" in after for _, after in plan.values()))
        updater.apply(plan)
        with self.assertRaisesRegex(ValueError, "new immutable tag"):
            updater.plan(self.root, "ios", "video", tag, updater.DEFAULT_REPO, "full", release)

    def test_default_flavor_entry_retains_its_platform_mapping(self):
        tag = "v10.0.0"
        release = self.release("macos", tag, ("audio", "video"), mode="default")
        plan = updater.plan(self.root, "macos", "all", tag, updater.DEFAULT_REPO, "default", release)
        for path, (_, after) in plan.items():
            expected = b"_macos-universal-audio-full" if "audio" in str(path) else b"_macos-universal-video-default"
            self.assertIn(expected, after)

    def test_full_video_inventory_expands_both_swift_tables_from_18_to_29(self):
        make, swift = self.legacy_video_fixture()
        tag = "v10.0.0-macos.1"
        release = self.inventory_release("macos", tag, VIDEO_29)
        before = self.snapshot()
        plan = updater.plan(self.root, "macos", "video", tag, updater.DEFAULT_REPO, "full", release)
        self.assertEqual(set(plan), {make, swift})
        self.assertEqual(self.snapshot(), before)
        updater.apply(plan)
        text = swift.read_text()
        targets = re.findall(r'"([A-Za-z0-9_-]+)"', re.search(
            r'^let libmpvTargets = \[(?s:.*?)^\]', text, re.M).group())
        checksums = dict(re.findall(r'^\s*"([A-Za-z0-9_-]+)": "([a-f0-9]{64})"',
                                    re.search(r'^let libmpvChecksums = \[(?s:.*?)^\]', text, re.M).group(), re.M))
        self.assertEqual(targets, VIDEO_29)
        self.assertEqual(set(checksums), set(VIDEO_29))
        for index, framework in enumerate(VIDEO_29, start=2):
            self.assertEqual(checksums[framework], f"{index:064x}")
        self.assertIn('"Shaderc_shared"', text)
        self.assertIn('"Glslang-default-resource-limits"', text)
        self.assertIn('"SPIRV-Tools-shared"', text)
        self.assertEqual({p for p in before if before[p] != self.snapshot()[p]},
                         {make.relative_to(self.root), swift.relative_to(self.root)})
        self.assertEqual(updater.plan(self.root, "macos", "video", tag,
                                      updater.DEFAULT_REPO, "full", release), {})

    def test_inventory_uses_only_selected_platform_variant_and_flavor(self):
        make, swift = self.legacy_video_fixture()
        tag = "v10.0.0"
        release = self.inventory_release("macos", tag, VIDEO_29)
        for platform, variant in (("macos", "audio"), ("ios", "video")):
            release["assets"].extend(self.inventory_release(platform, tag, ["Mpv", "Other"], variant)["assets"])
        release["assets"].append({"name": f"libmpv-xcframeworks_{tag}_macos-universal-video-default_Unselected.zip",
                                  "state": "uploaded", "digest": None})
        before = self.snapshot()
        plan = updater.plan(self.root, "macos", "video", tag, updater.DEFAULT_REPO, "full", release)
        self.assertEqual(set(plan), {make, swift})
        updater.apply(plan)
        after = self.snapshot()
        for path in before:
            if path not in {make.relative_to(self.root), swift.relative_to(self.root)}:
                self.assertEqual(before[path], after[path], path)
        self.assertNotIn('"Other"', swift.read_text())
        self.assertNotIn('"Unselected"', swift.read_text())

    def test_added_assets_are_validated_before_any_pin_changes(self):
        self.legacy_video_fixture()
        tag = "v10.0.0-macos.1"
        baseline = self.inventory_release("macos", tag, VIDEO_29)
        before = self.snapshot()
        for failure in ("missing-digest", "bad-digest", "not-uploaded", "duplicate", "case-conflict", "missing-known"):
            release = copy.deepcopy(baseline)
            added = next(asset for asset in release["assets"] if asset["name"].endswith("_Shaderc_shared.zip"))
            if failure == "missing-digest":
                added.pop("digest")
            elif failure == "bad-digest":
                added["digest"] = "sha256:invalid"
            elif failure == "not-uploaded":
                added["state"] = "new"
            elif failure == "duplicate":
                release["assets"].append(copy.deepcopy(added))
            elif failure == "case-conflict":
                extra = copy.deepcopy(added)
                extra["name"] = extra["name"].replace("Shaderc_shared", "shaderc_shared")
                release["assets"].append(extra)
            else:
                release["assets"] = [asset for asset in release["assets"] if not asset["name"].endswith("_Avformat.zip")]
            with self.subTest(failure=failure), self.assertRaises(ValueError):
                updater.plan(self.root, "macos", "video", tag, updater.DEFAULT_REPO, "full", release)
            self.assertEqual(self.snapshot(), before)

    def test_changed_zip_checksum_with_same_archive_tag_is_rejected(self):
        self.legacy_video_fixture()
        tag = "v10.0.0-macos.1"
        release = self.inventory_release("macos", tag, VIDEO_29)
        updater.apply(updater.plan(self.root, "macos", "video", tag,
                                    updater.DEFAULT_REPO, "full", release))
        before = self.snapshot()
        changed = copy.deepcopy(release)
        next(asset for asset in changed["assets"] if asset["name"].endswith("_Shaderc_shared.zip"))["digest"] = "sha256:" + "f" * 64
        with self.assertRaisesRegex(ValueError, "new immutable tag"):
            updater.plan(self.root, "macos", "video", tag, updater.DEFAULT_REPO, "full", changed)
        self.assertEqual(self.snapshot(), before)

    def test_correct_legacy_inventory_stays_idempotent(self):
        self.legacy_video_fixture()
        tag = "v10.0.0-macos.1"
        release = self.inventory_release("macos", tag, VIDEO_18)
        updater.apply(updater.plan(self.root, "macos", "video", tag,
                                    updater.DEFAULT_REPO, "full", release))
        self.assertEqual(updater.plan(self.root, "macos", "video", tag,
                                      updater.DEFAULT_REPO, "full", release), {})

    def test_apply_failure_rolls_back_the_selected_video_pair(self):
        _, swift = self.legacy_video_fixture()
        tag = "v10.0.0-macos.1"
        plan = updater.plan(self.root, "macos", "video", tag, updater.DEFAULT_REPO,
                            "full", self.inventory_release("macos", tag, VIDEO_29))
        before = self.snapshot()
        write = Path.write_bytes
        def failing_write(path, data):
            if path == swift and data == plan[swift][1]:
                raise OSError("simulated Swift pin write failure")
            return write(path, data)
        with patch.object(Path, "write_bytes", failing_write), self.assertRaises(OSError):
            updater.apply(plan)
        self.assertEqual(self.snapshot(), before)


if __name__ == "__main__":
    unittest.main()
