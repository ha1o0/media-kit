import copy
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

import update_darwin_libmpv_artifacts as updater


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
            keys = re.findall(r'^\s*"(\w+)": "[a-f0-9]{64}"', swift, re.M)
            names = [f"{stem}.tar.gz", *(f"{stem}_{key}.zip" for key in keys)]
            assets.extend({"name": name, "digest": "sha256:" + "5" * 64,
                           "state": "uploaded"} for name in names)
        return {"tag_name": tag, "draft": False, "assets": assets}

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


if __name__ == "__main__":
    unittest.main()
