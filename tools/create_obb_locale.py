"""Create an optional texts-only EDOPro locale from the supplied OBB's Vietnamese slot I."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sqlite3
import struct
import zipfile

TEXT_COLUMNS = ["id", "name", "desc"] + [f"str{i}" for i in range(1, 17)]


def digest(path: Path) -> str:
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def read_utf16(blob: bytes, offset: int) -> str:
    if type(offset) is not int or offset < 0 or offset % 2 or offset + 2 > len(blob):
        raise ValueError(f"Invalid UTF-16 byte offset: {offset}")
    for end in range(offset, len(blob) - 1, 2):
        if blob[end:end + 2] == b"\0\0":
            return blob[offset:end].decode("utf-16le", errors="strict")
    raise ValueError(f"Unterminated UTF-16 string at {offset}")


def create_locale(obb: Path, cdb: Path, mapping: dict[int, int], audit: dict, out_dir: Path) -> dict:
    """Write out_dir/obb-vi.cdb and locale-report.json; out_dir must not exist."""
    obb, cdb, out_dir = map(lambda p: Path(p).resolve(), (obb, cdb, out_dir))
    if out_dir.exists():
        raise FileExistsError(f"Refusing to replace existing locale directory: {out_dir}")
    if any(out_dir == source or out_dir in source.parents for source in (obb, cdb)):
        raise ValueError("Locale output must be separate from input files")
    obb_hash, cdb_hash = digest(obb), digest(cdb)
    if obb_hash != audit["sources"]["OBB"]["sha256"]:
        raise ValueError("OBB differs from mapping audit")
    cdb_hashes = {entry["sha256"] for name, entry in audit["sources"]["downloads"].items() if name.endswith(".cdb")}
    if cdb_hash not in cdb_hashes:
        raise ValueError("CDB differs from pinned mapping audit")
    approved = {int(key): value for key, value in audit["bridge"]["konamiToCoreCode"].items()}
    if any(type(kid) is not int or type(code) is not int or code <= 0 or approved.get(kid) != code
           for kid, code in mapping.items()) or mapping != approved:
        raise ValueError("Locale mapping must equal the audited positive core-code mapping")

    connection = sqlite3.connect(cdb.as_uri() + "?mode=ro", uri=True)
    try:
        english = {row[0]: row for row in connection.execute(
            "SELECT " + ",".join('"' + column + '"' for column in TEXT_COLUMNS) + " FROM texts")}
        metadata_ids = {row[0] for row in connection.execute("SELECT id FROM datas")}
    finally:
        connection.close()
    rows, skipped, present_ids = {}, [], set()
    empty_name, empty_description = 0, 0
    with zipfile.ZipFile(obb) as archive:
        for name in ("assets/CARD_Prop.bin", "assets/CARD_Indx_I.bin", "assets/CARD_Name_I.bin", "assets/CARD_Desc_I.bin"):
            if archive.namelist().count(name) != 1:
                raise ValueError(f"Missing or duplicate OBB table: {name}")
        props = archive.read("assets/CARD_Prop.bin")
        offsets = archive.read("assets/CARD_Indx_I.bin")
        names = archive.read("assets/CARD_Name_I.bin")
        descriptions = archive.read("assets/CARD_Desc_I.bin")
        if len(props) % 8 or len(offsets) != len(props) + 8:
            raise ValueError("Prop and localized offset table dimensions differ")
        if len(names) % 2 or len(descriptions) % 2:
            raise ValueError("Odd UTF-16 blob length")
        record_count = len(props) // 8
        for index in range(record_count):
            kid = struct.unpack_from("<I", props, index * 8)[0] & 0x3FFF
            name_offset, desc_offset = struct.unpack_from("<II", offsets, index * 8)
            local_name = read_utf16(names, name_offset)
            local_description = read_utf16(descriptions, desc_offset)
            if kid == 0:
                if index != 0 or local_name or local_description:
                    raise ValueError("Unexpected empty card record")
                continue
            if kid in present_ids:
                raise ValueError(f"Duplicate source Konami ID: {kid}")
            present_ids.add(kid)
            if kid not in mapping:
                skipped.append(kid)
                continue
            code = mapping[kid]
            if code not in english or code not in metadata_ids:
                raise ValueError(f"Mapped core code lacks full database row: {code}")
            if code in rows:
                raise ValueError(f"Locale mapping collapses two source cards to core code: {code}")
            original = english[code]
            empty_name += not bool(local_name)
            empty_description += not bool(local_description)
            rows[code] = (code, local_name or original[1], local_description or original[2], *original[3:])
    if not rows:
        raise ValueError("No mapped localized card records")

    out_dir.mkdir(parents=True)
    target = out_dir / "obb-vi.cdb"
    output = sqlite3.connect(target)
    try:
        output.execute('CREATE TABLE texts (id INTEGER PRIMARY KEY, name TEXT, "desc" TEXT, ' +
                       ", ".join(f"str{i} TEXT" for i in range(1, 17)) + ")")
        output.executemany("INSERT INTO texts VALUES (" + ",".join("?" for _ in TEXT_COLUMNS) + ")",
                           [rows[code] for code in sorted(rows)])
        output.commit()
        if output.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise ValueError("Locale SQLite integrity check failed")
        if output.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall() != [("texts",)]:
            raise ValueError("Locale must contain only texts, never datas")
        if output.execute("SELECT * FROM texts ORDER BY id").fetchall() != [rows[code] for code in sorted(rows)]:
            raise ValueError("Locale values changed during serialization")
    finally:
        output.close()
    if digest(obb) != obb_hash or digest(cdb) != cdb_hash:
        raise ValueError("Input changed while creating locale")
    report = {
        "locale": "vi-obb", "database": "obb-vi.cdb", "tables": ["texts"],
        "sourceSlot": "I", "sourceLanguage": "Vietnamese descriptions in supplied modified OBB; card names retained from source",
        "sourceEra": "Legacy Duel Generation OBB text; may disagree with current EDOPro effects/errata",
        "sourceOBBSHA256": obb_hash, "baseCDBSHA256": cdb_hash, "localeCDBSHA256": digest(target),
        "rawRecordsIncludingEmpty": record_count, "localizedCards": len(rows),
        "skippedUnmappedSourceIDs": skipped,
        "mappedIDsAbsentFromSource": sorted(set(mapping) - present_ids),
        "emptySourceNameFallbacks": empty_name, "emptySourceDescriptionFallbacks": empty_description,
        "effectPrompts": "str1..str16 preserved byte-for-text-value from English CDB, including null values",
        "metadataModified": False, "defaultLocaleChanged": False, "sourceInputsUnchanged": True,
        "sqliteIntegrityCheck": "ok", "runtimeVerified": False,
    }
    (out_dir / "locale-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--obb", type=Path, required=True)
    parser.add_argument("--cdb", type=Path, required=True)
    parser.add_argument("--audit", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True, help="New locale folder, normally config/languages/vi-obb")
    args = parser.parse_args()
    audit = json.loads(args.audit.read_text(encoding="utf-8"))
    mapping = {int(key): value for key, value in audit["bridge"]["konamiToCoreCode"].items()}
    report = create_locale(args.obb, args.cdb, mapping, audit, args.out)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
