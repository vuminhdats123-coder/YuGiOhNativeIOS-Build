"""Tests the Git patch applicator. Objective-C startup is inspected, not executed."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("native_patches", ROOT / "tools/apply_native_patches.py")
patches = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(patches)


class NativePatchTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="edopro-patch-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.repo = self.root / "client"
        self.repo.mkdir()
        self.run_git("init", "--quiet")
        self.run_git("config", "core.autocrlf", "false")
        self.target = self.repo / patches.TARGET
        self.target.parent.mkdir(parents=True)
        self.original = "// fixture\nint bootstrap() { return 0; }\n// untouched\n"
        self.updated = "// fixture\nint bootstrap() { return 1; }\n// untouched\n"
        self.target.write_text(self.original, encoding="utf-8")
        (self.repo / "other.txt").write_text("keep\n", encoding="utf-8")
        self.run_git("add", ".")
        self.run_git("-c", "user.name=Patch Test", "-c", "user.email=patch-test@example.invalid", "commit", "-qm", "fixture")
        self.revision = self.run_git("rev-parse", "HEAD").decode().strip()
        self.target.write_text(self.updated, encoding="utf-8")
        self.patch = self.root / "reviewed.patch"
        self.patch.write_bytes(self.run_git("diff", "--", patches.TARGET))
        self.target.write_text(self.original, encoding="utf-8")

    def run_git(self, *arguments):
        return subprocess.run(["git", "-C", str(self.repo), *arguments], capture_output=True, check=True).stdout

    def apply(self):
        return patches.apply_native_patch(self.repo, self.patch, expected_revision=self.revision)

    def test_apply_twice_is_idempotent(self):
        self.assertEqual(self.apply(), "applied")
        first = self.target.read_bytes()
        self.assertEqual(self.apply(), "already-applied")
        self.assertEqual(self.target.read_bytes(), first)
        self.assertEqual(self.target.read_text(encoding="utf-8"), self.updated)

    def test_read_only_check_rejects_unpatched_file_without_mutation(self):
        with self.assertRaisesRegex(patches.PatchError, "has not been applied"):
            patches.apply_native_patch(self.repo, self.patch, expected_revision=self.revision, check_only=True)
        self.assertEqual(self.target.read_text(encoding="utf-8"), self.original)
        self.assertEqual(self.run_git("status", "--porcelain"), b"")

    def test_read_only_check_accepts_exact_applied_patch(self):
        self.apply()
        before = self.target.read_bytes()
        self.assertEqual(patches.apply_native_patch(self.repo, self.patch, expected_revision=self.revision,
                                                    check_only=True), "already-applied")
        self.assertEqual(self.target.read_bytes(), before)

    def test_wrong_revision_leaves_file_untouched(self):
        with self.assertRaisesRegex(patches.PatchError, "revision"):
            patches.apply_native_patch(self.repo, self.patch, expected_revision="0" * 40)
        self.assertEqual(self.target.read_text(encoding="utf-8"), self.original)

    def test_unrelated_edit_is_preserved_and_rejected(self):
        (self.repo / "other.txt").write_text("user edit\n", encoding="utf-8")
        with self.assertRaisesRegex(patches.PatchError, "unrelated"):
            self.apply()
        self.assertEqual((self.repo / "other.txt").read_text(encoding="utf-8"), "user edit\n")
        self.assertEqual(self.target.read_text(encoding="utf-8"), self.original)

    def test_extra_edits_in_already_patched_file_are_rejected(self):
        self.apply()
        self.target.write_text(self.updated + "// user addition\n", encoding="utf-8")
        with self.assertRaisesRegex(patches.PatchError, "beyond"):
            self.apply()
        self.assertIn("user addition", self.target.read_text(encoding="utf-8"))

    def test_staged_edit_is_rejected(self):
        self.target.write_text(self.updated, encoding="utf-8")
        self.run_git("add", patches.TARGET)
        with self.assertRaisesRegex(patches.PatchError, "staged"):
            self.apply()

    def test_untracked_file_is_rejected(self):
        (self.repo / "user.txt").write_text("keep", encoding="utf-8")
        with self.assertRaisesRegex(patches.PatchError, "unrelated"):
            self.apply()
        self.assertTrue((self.repo / "user.txt").exists())

    def test_other_patch_target_is_rejected(self):
        self.patch.write_bytes(self.patch.read_bytes().replace(patches.TARGET.encode(), b"other.txt"))
        with self.assertRaisesRegex(patches.PatchError, "only"):
            self.apply()
        self.assertEqual(self.target.read_text(encoding="utf-8"), self.original)

    def integration_fixture(self):
        native = self.root / "NativeClient"
        (native / "patches").mkdir(parents=True)
        (native / "overlays").mkdir()
        (native / "patches/bootstrap.patch").write_bytes(self.patch.read_bytes())
        (native / "overlays/helper.h").write_bytes(b"// native overlay\n")
        manifest = {"schemaVersion": 1,
                    "patches": [{"file": "patches/bootstrap.patch", "targets": [patches.TARGET]}],
                    "overlays": [{"source": "overlays/helper.h", "target": "gframe/helper.h"}]}
        series = native / "patches/series.json"
        series.write_text(json.dumps(manifest), encoding="utf-8")
        return series, manifest

    def test_integration_materializes_and_checks_both_patch_and_overlay(self):
        series, _ = self.integration_fixture()
        options = dict(expected_revision=self.revision)
        self.assertEqual(patches.apply_native_integration(self.repo, series, **options), "applied")
        self.assertEqual((self.repo / "gframe/helper.h").read_bytes(), b"// native overlay\n")
        self.assertEqual(patches.apply_native_integration(self.repo, series, check_only=True, **options), "already-applied")
        (self.repo / "gframe/helper.h").write_text("user edit", encoding="utf-8")
        with self.assertRaisesRegex(patches.PatchError, "beyond"):
            patches.apply_native_integration(self.repo, series, **options)
        self.assertEqual((self.repo / "gframe/helper.h").read_text(), "user edit")

    def test_overlay_conflict_does_not_partially_apply_other_files(self):
        series, _ = self.integration_fixture()
        (self.repo / "gframe/helper.h").write_text("keep user content", encoding="utf-8")
        with self.assertRaisesRegex(patches.PatchError, "beyond"):
            patches.apply_native_integration(self.repo, series, expected_revision=self.revision)
        self.assertEqual(self.target.read_text(encoding="utf-8"), self.original)

    def test_overlay_cannot_replace_tracked_upstream_file(self):
        series, manifest = self.integration_fixture()
        manifest['overlays'][0]['target'] = "other.txt"
        series.write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaisesRegex(patches.PatchError, "tracked upstream"):
            patches.apply_native_integration(self.repo, series, expected_revision=self.revision)
        self.assertEqual((self.repo / "other.txt").read_text(), "keep\n")

    def test_overlay_traversal_and_duplicate_targets_rejected(self):
        series, manifest = self.integration_fixture()
        manifest['overlays'][0]['target'] = "../escape.h"
        series.write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaisesRegex(patches.PatchError, "Unsafe"):
            patches.apply_native_integration(self.repo, series, expected_revision=self.revision)
        manifest['overlays'][0]['target'] = "gframe/helper.h"
        manifest['overlays'].append(manifest['overlays'][0])
        series.write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaisesRegex(patches.PatchError, "Duplicate"):
            patches.apply_native_integration(self.repo, series, expected_revision=self.revision)


class BootstrapSourceContract(unittest.TestCase):
    def test_bootstrap_contract_in_patch(self):
        # This checks the reviewed patch contract; it does not claim filesystem/UIKit runtime success.
        patch = patches.PATCH.read_text(encoding="utf-8-sig")
        added = "\n".join(line[1:] for line in patch.splitlines() if line.startswith("+") and not line.startswith("+++"))
        for required in ["cards.cdb", "script/constant.lua", "script/utility.lua", "config/strings.conf",
                         "fonts/NotoSansJP-Regular.otf", "package-manifest.json", "offline-ai/offline_ai.js"]:
            self.assertIn(required, added)
        self.assertIn("NSJSONSerialization", added)
        self.assertIn("isEqualToData:bundledManifest", added)
        self.assertIn(".EDOPro-staging-", added)
        self.assertIn("copyItemAtURL:bundledGame toURL:staging", added)
        self.assertIn("moveItemAtURL:staging toURL:destination", added)
        self.assertIn("hasNoSymbolicLinks", added)
        self.assertIn("destinationExists", added)
        self.assertIn("@\"deck\"", added)
        self.assertIn("@\"replay\"", added)
        self.assertIn("@\"config/system.conf\"", added)
        self.assertIn("@\"config/campaign-progress.json\"", added)
        self.assertIn(".EDOPro-backup-", added)
        self.assertIn("Nothing was overwritten", added)
        self.assertIn("if(gameRoot.empty())", added)
        self.assertIn("DIAG phase=workdir.ready", added)
        self.assertIn("DIAG phase=edopro_main.enter", added)
        self.assertIn("DIAG phase=edopro_main.exit code={}", added)
        self.assertNotIn("[filemgr release]", added)
        self.assertNotIn("removeItemAtURL:destination", added)
        self.assertNotIn("replaceItemAtURL:destination", added)


if __name__ == "__main__":
    unittest.main()
