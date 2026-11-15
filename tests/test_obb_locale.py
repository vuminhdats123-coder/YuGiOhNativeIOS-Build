from pathlib import Path
import sqlite3
import struct
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from create_obb_locale import TEXT_COLUMNS, create_locale, digest, read_utf16


class LocaleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.cdb = self.root / "cards.cdb"
        with sqlite3.connect(self.cdb) as db:
            db.execute("CREATE TABLE datas (id INTEGER PRIMARY KEY, atk INTEGER)")
            db.execute('CREATE TABLE texts (id INTEGER PRIMARY KEY, name TEXT, "desc" TEXT, ' +
                       ",".join(f"str{i} TEXT" for i in range(1, 17)) + ")")
            self.prompts = tuple(None if i == 5 else f"English action {i}" for i in range(1, 17))
            db.execute("INSERT INTO datas VALUES (?,?)", (12345678, 3000))
            db.execute("INSERT INTO texts VALUES (" + ",".join("?" for _ in TEXT_COLUMNS) + ")",
                       (12345678, "English name", "English effect", *self.prompts))
        db.close()
        self.obb = self.root / "source.obb"
        self.create_obb()
        self.mapping = {4007: 12345678, 10855: 87654321}
        self.audit = {"sources": {"OBB": {"sha256": digest(self.obb)},
                                  "downloads": {"cards.cdb": {"sha256": digest(self.cdb)}}},
                      "bridge": {"konamiToCoreCode": {str(k): v for k, v in self.mapping.items()}}}

    def tearDown(self):
        self.temp.cleanup()

    def create_obb(self, bad_offset=False):
        name_blob = b"\0\0" + "Rồng A\u0100\0".encode("utf-16le")
        desc_blob = b"\0\0" + "Mô tả tiếng Việt cũ.\0".encode("utf-16le")
        offsets = struct.pack("<IIIIII", 0, 0, 3 if bad_offset else 2, 2, len(name_blob), len(desc_blob))
        with zipfile.ZipFile(self.obb, "w") as archive:
            archive.writestr("assets/CARD_Prop.bin", bytes(8) + struct.pack("<II", 4007, 0))
            archive.writestr("assets/CARD_Indx_I.bin", offsets)
            archive.writestr("assets/CARD_Name_I.bin", name_blob)
            archive.writestr("assets/CARD_Desc_I.bin", desc_blob)

    def test_utf16_alignment_and_bounds(self):
        self.assertEqual(read_utf16("A\u0100B\0".encode("utf-16le"), 0), "A\u0100B")
        for offset in (-2, 1, 4):
            with self.assertRaises(ValueError):
                read_utf16(b"A\0\0\0", offset)
        with self.assertRaises(ValueError):
            read_utf16(b"A\0", 0)

    def test_texts_only_and_english_prompts_preserved(self):
        original_obb, original_cdb = digest(self.obb), digest(self.cdb)
        report = create_locale(self.obb, self.cdb, self.mapping, self.audit, self.root / "vi-obb")
        with sqlite3.connect(self.root / "vi-obb/obb-vi.cdb") as db:
            self.assertEqual(db.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall(), [("texts",)])
            row = db.execute("SELECT * FROM texts").fetchone()
            self.assertEqual(row[:3], (12345678, "Rồng A\u0100", "Mô tả tiếng Việt cũ."))
            self.assertEqual(row[3:], self.prompts)
            self.assertEqual(db.execute("PRAGMA integrity_check").fetchone()[0], "ok")
        db.close()
        self.assertEqual(digest(self.obb), original_obb)
        self.assertEqual(digest(self.cdb), original_cdb)
        self.assertEqual(report["localizedCards"], 1)
        self.assertEqual(report["mappedIDsAbsentFromSource"], [10855])
        self.assertFalse(report["metadataModified"])
        self.assertFalse(report["defaultLocaleChanged"])

    def test_deterministic_output(self):
        first = create_locale(self.obb, self.cdb, self.mapping, self.audit, self.root / "first")
        second = create_locale(self.obb, self.cdb, self.mapping, self.audit, self.root / "second")
        self.assertEqual(first, second)
        self.assertEqual((self.root / "first/obb-vi.cdb").read_bytes(), (self.root / "second/obb-vi.cdb").read_bytes())
        self.assertEqual((self.root / "first/locale-report.json").read_bytes(), (self.root / "second/locale-report.json").read_bytes())

    def test_corrupt_offsets_do_not_create_output(self):
        self.create_obb(bad_offset=True)
        self.audit["sources"]["OBB"]["sha256"] = digest(self.obb)
        with self.assertRaises(ValueError):
            create_locale(self.obb, self.cdb, self.mapping, self.audit, self.root / "invalid")
        self.assertFalse((self.root / "invalid").exists())

    def test_source_hash_and_mapping_must_match_audit(self):
        with self.assertRaises(ValueError):
            create_locale(self.obb, self.cdb, {4007: 1}, self.audit, self.root / "invalid-map")
        self.audit["sources"]["OBB"]["sha256"] = "0" * 64
        with self.assertRaises(ValueError):
            create_locale(self.obb, self.cdb, self.mapping, self.audit, self.root / "invalid-hash")

    def test_existing_output_not_overwritten(self):
        output = self.root / "existing"
        output.mkdir()
        marker = output / "keep.txt"
        marker.write_text("preserve")
        with self.assertRaises(FileExistsError):
            create_locale(self.obb, self.cdb, self.mapping, self.audit, output)
        self.assertEqual(marker.read_text(), "preserve")


if __name__ == "__main__":
    unittest.main()
