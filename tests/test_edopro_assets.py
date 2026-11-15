import importlib.util
from contextlib import closing
from io import BytesIO
import json
from pathlib import Path
import sqlite3
import struct
import tempfile
import unittest
import zipfile
from PIL import Image

SPEC = importlib.util.spec_from_file_location("prepare_edopro_assets", Path(__file__).parents[1] / "tools/prepare_edopro_assets.py")
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


def ydc(main, extra=(), side=()):
    data = struct.pack("<Q", 0x5823)
    for cards in (main, extra, side):
        data += struct.pack("<H", len(cards)) + struct.pack(f"<{len(cards)}H", *cards)
    return data


class AssetTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.base = self.root / "base"
        for relative in ("config/strings.conf", "config/system.conf", "fonts/NotoSansJP-Regular.otf", "LICENSE"):
            target = self.base / relative
            target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(b"fixture")
        (self.base / "config/configs.json").write_text('{"repos":[{"url":"mutable"}],"urls":[],"servers":[]}', encoding="utf-8")
        for name in builder.TEXTURES:
            target = self.base / "textures" / f"{name}.png"
            target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(b"fixture png")
        self.cdb = self.root / "cards.cdb"
        with closing(sqlite3.connect(self.cdb)) as db:
            db.execute("CREATE TABLE datas(id INTEGER PRIMARY KEY,type INTEGER,alias INTEGER)")
            db.execute("CREATE TABLE texts(id INTEGER PRIMARY KEY,name TEXT)")
            for code in range(101, 115):
                db.execute("INSERT INTO datas VALUES(?,?,0)", (code, 0x11))
                db.execute("INSERT INTO texts VALUES(?,?)", (code, f"Card {code}"))
            db.commit()
        self.obb = self.root / "source.obb"
        ids = [3900 + index for index in range(14)]
        self.main = [kid for kid in ids for _ in range(3)][:40]
        with zipfile.ZipFile(self.obb, "w") as archive:
            archive.writestr("assets/CARD_Prop.bin", bytes(8) + b"".join(struct.pack("<II", kid, 0) for kid in ids))
            archive.writestr("assets/CARD_Pass.bin", struct.pack("<15I", 0, *range(101, 115)))
            archive.writestr("assets/full.ydc", ydc(self.main))
            archive.writestr("assets/missing.ydc", ydc(self.main[:-1] + [9999]))
            archive.writestr("assets/support.ydc", ydc(self.main[:9]))
            archive.writestr("assets/3900.jpg", b"canonical art")
            archive.writestr("assets/03900.jpg", b"alternate art")
            archive.writestr("assets/menu.jpg", b"unmapped art")
            archive.writestr("assets/bgm_menu.mp3", b"original menu mp3")
            archive.writestr("assets/duel_1.mp3", b"original duel mp3")
            archive.writestr("assets/DUEL_END.mp3", b"original opaque sfx")
        self.scripts = self.root / "CardScripts-pinned.zip"
        with zipfile.ZipFile(self.scripts, "w") as archive:
            for name, data in {"constant.lua": "constant library", "utility.lua": "full utility library",
                               "official/c101.lua": "current effect", "pre-errata/c101.lua": "old effect",
                               "COPYING": "script licence"}.items():
                archive.writestr("CardScripts-pin/" + name, data)
        self.audit_path = self.root / "audit.json"
        self.audit = {"sources": {"OBB": {"sha256": builder.digest(self.obb)},
                                  "downloads": {"cards.cdb": {"sha256": builder.digest(self.cdb)},
                                                self.scripts.name: {"sha256": builder.digest(self.scripts)}},
                                  "BabelCDB": {"commit": "a" * 40}, "CardScripts": {"commit": "b" * 40}},
                      "bridge": {"konamiToCoreCode": {str(kid): 101 + index for index, kid in enumerate(ids)}}}
        self.save_audit()

    def save_audit(self):
        self.audit_path.write_text(json.dumps(self.audit), encoding="utf-8")

    def prepare(self, name="game"):
        return builder.prepare(self.obb, self.cdb, self.scripts, self.base, self.audit_path, self.root / name)

    def test_preserves_inputs_decks_images_and_scripts(self):
        before = builder.digest(self.obb)
        report = self.prepare()
        game = self.root / "game"
        self.assertEqual(before, builder.digest(self.obb))
        self.assertEqual((report["deckCount"], report["mappedDecks"], report["unresolvedDecks"], report["localDuelDecks"]), (3, 2, 1, 1))
        self.assertEqual((game / "pics/101.jpg").read_bytes(), b"canonical art")
        self.assertEqual((game / "obb-art/assets/03900.jpg").read_bytes(), b"alternate art")
        self.assertTrue((game / "obb-art/assets/menu.jpg").is_file())
        self.assertEqual((report["sourceMP3s"], report["mappedMusicFiles"]), (3, 2))
        self.assertEqual((game / "sound/BGM/menu/obb-menu.mp3").read_bytes(), b"original menu mp3")
        self.assertEqual((game / "obb-audio/assets/DUEL_END.mp3").read_bytes(), b"original opaque sfx")
        self.assertEqual((game / "script/c101.lua").read_text(), "current effect")
        self.assertEqual((game / "script/pre-errata/c101.lua").read_text(), "old effect")
        self.assertTrue((game / "script/COPYING").is_file())
        self.assertEqual((game / "unresolved-decks/assets/missing.ydc").read_bytes(), ydc(self.main[:-1] + [9999]))
        decks = json.loads((game / "reports/decks.json").read_text())
        missing = next(row for row in decks if row["unresolved"])
        self.assertEqual(missing["coreCodes"]["main"][-1], None)
        self.assertFalse((game / "deck" / builder.client_deck_filename("assets/missing.ydc")).exists())
        self.assertTrue((game / "converted-decks/assets/support.ydk").exists())
        self.assertFalse((game / "deck" / builder.client_deck_filename("assets/support.ydc")).exists())
        self.assertEqual(len(list((game / "deck").glob("*.ydk"))), report["localDuelDecks"])
        config = json.loads((game / "config/configs.json").read_text())
        self.assertEqual(config["repos"], [])
        self.assertIn("noClientUpdates = 1", (game / "config/system.conf").read_text())
        for relative, entry in report["files"].items():
            self.assertEqual(builder.digest(game / relative), entry["sha256"])

    def test_manifest_is_deterministic(self):
        self.prepare("one"); self.prepare("two")
        self.assertEqual((self.root / "one/package-manifest.json").read_bytes(),
                         (self.root / "two/package-manifest.json").read_bytes())

    def test_same_basename_decks_are_distinct_and_visible_without_recursion(self):
        with zipfile.ZipFile(self.obb, "a") as archive:
            archive.writestr("assets/another/full.ydc", ydc(self.main))
        self.audit["sources"]["OBB"]["sha256"] = builder.digest(self.obb); self.save_audit()
        report = self.prepare()
        files = list((self.root / "game/deck").glob("*.ydk"))
        self.assertEqual(len(files), 2)
        self.assertEqual(len(files), report["localDuelDecks"])
        self.assertEqual(len({path.name for path in files}), 2)
        self.assertTrue(all(path.name.startswith("OBB_full_") for path in files))

    def test_existing_output_is_not_overwritten(self):
        output = self.root / "game"; output.mkdir()
        marker = output / "keep.txt"; marker.write_text("unchanged")
        with self.assertRaises(FileExistsError): self.prepare()
        self.assertEqual(marker.read_text(), "unchanged")

    def test_native_ai_module_is_bundled_verbatim_and_hashed(self):
        decision = self.root / "offline_ai.js"
        decision.write_bytes(b"'use strict'; globalThis.OfflineDuelAI = {};\n")
        report = builder.prepare(self.obb, self.cdb, self.scripts, self.base, self.audit_path,
                                 self.root / "native", offline_ai=decision)
        bundled = self.root / "native/offline-ai/offline_ai.js"
        self.assertTrue(report['offlineAIIncluded'])
        self.assertEqual(bundled.read_bytes(), decision.read_bytes())
        self.assertEqual(report['files']['offline-ai/offline_ai.js']['sha256'], builder.digest(decision))
        with self.assertRaisesRegex(ValueError, "Missing offline AI"):
            builder.prepare(self.obb, self.cdb, self.scripts, self.base, self.audit_path,
                            self.root / "missing-ai", offline_ai=self.root / "missing.js")
        self.assertFalse((self.root / "missing-ai").exists())

    @staticmethod
    def png(color):
        output = BytesIO()
        Image.new("RGBA", (3, 2), color).save(output, format="PNG")
        return output.getvalue()

    def test_only_reviewed_ui_images_replace_client_aliases(self):
        card_back = self.png((130, 60, 20, 255))
        menu = self.png((20, 20, 130, 255))
        empty = self.png((255, 255, 255, 0))
        (self.base / "textures/cover2.png").write_bytes(b"old opponent back")
        (self.base / "textures/bg_menu.png").write_bytes(b"old menu")
        with zipfile.ZipFile(self.obb, "a") as archive:
            archive.writestr("assets/card_rear.png", card_back)
            archive.writestr("assets/cir_bg.png", menu)
            for name in ("mainMenuBg.png", "gs_background.png", "gamescreen_bg.png", "unreviewed.png"):
                archive.writestr("assets/" + name, empty)
        before = builder.digest(self.obb)
        self.audit["sources"]["OBB"]["sha256"] = before; self.save_audit()
        report = self.prepare()
        game = self.root / "game"
        for name in ("cover.png", "cover2.png"):
            self.assertEqual((game / "textures" / name).read_bytes(), card_back)
        self.assertEqual((game / "textures/bg_menu.png").read_bytes(), menu)
        self.assertEqual((game / "textures/bg.png").read_bytes(), b"fixture png")
        rows = report["originalUITextures"]
        self.assertEqual({row["output"] for row in rows}, {"textures/cover.png", "textures/cover2.png", "textures/bg_menu.png"})
        self.assertTrue(all(row["dimensions"] == [3, 2] and row["alphaRange"] == [255, 255] for row in rows))
        self.assertTrue(all(row["replacedBaseSHA256"] for row in rows))
        for row in rows:
            self.assertEqual(row["sha256"], builder.digest(game / row["output"]))
        self.assertEqual(json.loads((game / "reports/ui-textures.json").read_text()), rows)
        self.assertEqual(builder.digest(self.obb), before)

    def test_invalid_or_transparent_reviewed_ui_png_is_rejected(self):
        original = self.obb.read_bytes()
        for index, data in enumerate((b"not a PNG", self.png((255, 255, 255, 0)))):
            with self.subTest(index=index):
                self.obb.write_bytes(original)
                with zipfile.ZipFile(self.obb, "a") as archive:
                    archive.writestr("assets/card_rear.png", data)
                self.audit["sources"]["OBB"]["sha256"] = builder.digest(self.obb); self.save_audit()
                with self.assertRaisesRegex(ValueError, "Invalid UI PNG|transparent UI PNG"):
                    self.prepare(f"invalid-ui-{index}")
                self.assertFalse((self.root / f"invalid-ui-{index}").exists())

    def test_hash_mismatch_fails_before_output(self):
        self.audit["sources"]["OBB"]["sha256"] = "0" * 64; self.save_audit()
        with self.assertRaisesRegex(ValueError, "OBB hash"): self.prepare()
        self.assertFalse((self.root / "game").exists())

    def test_traversal_in_scripts_is_rejected(self):
        with zipfile.ZipFile(self.scripts, "a") as archive: archive.writestr("../escape.lua", "bad")
        self.audit["sources"]["downloads"][self.scripts.name]["sha256"] = builder.digest(self.scripts); self.save_audit()
        with self.assertRaisesRegex(ValueError, "Unsafe asset path"): self.prepare()
        self.assertFalse((self.root / "escape.lua").exists())

    def test_normalized_archive_duplicates_are_rejected(self):
        with zipfile.ZipFile(self.scripts, "a") as archive:
            archive.writestr("CardScripts-pin/official/./c101.lua", "duplicate path")
        self.audit["sources"]["downloads"][self.scripts.name]["sha256"] = builder.digest(self.scripts); self.save_audit()
        with self.assertRaisesRegex(ValueError, "Duplicate"): self.prepare()

    def test_additional_review_does_not_reject_existing_audit_provenance(self):
        self.audit["bridge"]["reviewedRemaps"] = [{"konamiID": 3900, "coreCode": 101,
            "name": "Card 101", "provenance": "pinned source", "method": "explicitReviewedRemap"}]
        self.save_audit()
        review = self.root / "review.json"
        review.write_text('{"entries": []}', encoding="utf-8")
        result = builder.prepare(self.obb, self.cdb, self.scripts, self.base, self.audit_path,
                                 self.root / "game", reviewed_mappings=review)
        self.assertEqual(result["mappedDecks"], 2)

    def test_invalid_mapping_and_truncated_ydc_are_rejected(self):
        self.audit["bridge"]["konamiToCoreCode"]["3900"] = 99999; self.save_audit()
        with self.assertRaisesRegex(ValueError, "outside"): self.prepare()
        with self.assertRaisesRegex(ValueError, "Truncated"): builder.decode_deck(ydc(self.main)[:-3])

    def test_missing_boot_texture_is_not_silently_replaced(self):
        (self.base / "textures/cover.png").unlink()
        with self.assertRaisesRegex(ValueError, "Missing EDOPro base assets"): self.prepare()


if __name__ == "__main__":
    unittest.main()
