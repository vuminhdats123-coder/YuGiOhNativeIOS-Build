"""Fixture-only resource/dependency checks. No native tools or builds are run."""
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


resources = load("ios_resources", "NativeClient/overlays/ios-config/copy_bundle_resources.py")
dependencies = load("ios_dependencies", "NativeClient/iOS/audit_dependencies.py")


class ResourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source with spaces"
        self.source.mkdir()
        self.bundle = self.root / "YuGiOh.app"
        self.bundle.mkdir()
        self.icons = self.root / "icons"
        self.icons.mkdir()
        for name in resources.ICON_NAMES:
            (self.icons / name).write_bytes(b"\x89PNG\r\n\x1a\nfixture")
        (self.icons / "Assets.car").write_bytes(b"must not copy")
        (self.icons / "CodeResources").write_bytes(b"must not copy")
        self.files = {name: name.encode() for name in resources.REQUIRED}
        self.files.update({"deck/deck.ydk": b"main deck", "converted-decks/sub/deck.ydk": b"converted deck"})
        self.write_payload()

    def write_payload(self):
        manifest = {"schemaVersion": 1, "files": {}}
        for name, data in self.files.items():
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            manifest["files"][name] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        (self.source / "package-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")

    def test_preserves_tree_icons_and_other_bundle_resources(self):
        (self.bundle / "ygopro").write_bytes(b"unchanged executable fixture")
        result = resources.copy_resources(self.source, self.icons, self.bundle)
        self.assertEqual(result["files"], len(self.files))
        self.assertEqual((self.bundle / "game/converted-decks/sub/deck.ydk").read_bytes(), b"converted deck")
        self.assertEqual((self.bundle / "game/deck/deck.ydk").read_bytes(), b"main deck")
        self.assertFalse((self.bundle / "deck.ydk").exists())
        self.assertFalse((self.bundle / "Assets.car").exists())
        self.assertFalse((self.bundle / "CodeResources").exists())
        self.assertEqual((self.bundle / "ygopro").read_bytes(), b"unchanged executable fixture")

    def test_corruption_keeps_previous_payload_intact(self):
        resources.copy_resources(self.source, self.icons, self.bundle)
        (self.source / "cards.cdb").write_bytes(b"corrupt")
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            resources.copy_resources(self.source, self.icons, self.bundle)
        self.assertEqual((self.bundle / "game/cards.cdb").read_bytes(), self.files["cards.cdb"])
        self.assertFalse(list(self.bundle.glob(".edopro-game-*")))

    def test_replaces_only_valid_managed_game_directory(self):
        resources.copy_resources(self.source, self.icons, self.bundle)
        (self.source / "converted-decks/sub/deck.ydk").unlink()
        del self.files["converted-decks/sub/deck.ydk"]
        self.files["cards.cdb"] = b"new database"
        self.write_payload()
        resources.copy_resources(self.source, self.icons, self.bundle)
        self.assertEqual((self.bundle / "game/cards.cdb").read_bytes(), b"new database")
        self.assertFalse((self.bundle / "game/converted-decks/sub/deck.ydk").exists())
        self.assertFalse(list(self.bundle.glob(".edopro-game-*")))

    def test_rejects_unlisted_asset_and_foreign_destination(self):
        (self.source / "unexpected.txt").write_text("extra")
        with self.assertRaisesRegex(ValueError, "inventory"):
            resources.copy_resources(self.source, self.icons, self.bundle)
        (self.source / "unexpected.txt").unlink()
        (self.bundle / "game").mkdir()
        (self.bundle / "game/private.txt").write_text("preserve")
        with self.assertRaises(OSError):
            resources.copy_resources(self.source, self.icons, self.bundle)
        self.assertEqual((self.bundle / "game/private.txt").read_text(), "preserve")

    def test_rejects_unsafe_paths_and_non_app_target(self):
        for value in ("../escape", "/absolute", "a/./b", "a//b", "C:/escape", "a\\b"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                resources.safe_relative(value)
        with self.assertRaisesRegex(ValueError, "app directory"):
            resources.copy_resources(self.source, self.icons, self.root)

    def test_rejects_symlinks(self):
        try:
            (self.source / "link").symlink_to(self.source / "cards.cdb")
        except OSError:
            self.skipTest("Host does not permit creating symlinks")
        with self.assertRaisesRegex(ValueError, "regular file"):
            resources.copy_resources(self.source, self.icons, self.bundle)


def ar_object(cpu=0x0100000C, platform=2):
    command = struct.pack("<6I", 0x32, 24, platform, 16 << 16, 16 << 16, 0)
    body = struct.pack("<8I", 0xFEEDFACF, cpu, 0, 1, 1, len(command), 0, 0) + command
    header = b"fixture.o/".ljust(16) + b"0".ljust(12) + b"0".ljust(6) * 2 + b"100644".ljust(8) + str(len(body)).encode().ljust(10) + b"`\n"
    return b"!<arch>\n" + header + body


class DependencyTests(unittest.TestCase):
    def test_reads_ios_arm64_without_loading_native_code(self):
        result = dependencies.inspect_archive(ar_object())
        self.assertEqual(result["objects"], 1)
        self.assertEqual(result["platform"], "iPhoneOS")

    def test_rejects_simulator_wrong_arch_and_truncation(self):
        for payload in (ar_object(platform=7), ar_object(cpu=0x01000007), ar_object()[:-1]):
            with self.subTest(payload=payload[:16]), self.assertRaises(ValueError):
                dependencies.inspect_archive(payload)


if __name__ == "__main__":
    unittest.main()
