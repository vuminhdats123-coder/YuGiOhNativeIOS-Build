"""Read-only OBB/EDOPro coverage audit. Downloads references only with --fetch; never builds or executes Lua."""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import struct
import urllib.request
import zipfile

from verify_duel_data import encode_ydc, text_at

PROJECT = Path(__file__).resolve().parents[1]
ROOT = PROJECT.parent
DB_SHA = "6e21009855ed5f3b5966a24545bd0db393d44697"
SCRIPTS_SHA = "14f3b8905ff95a8f869fd6891aec4d6b580db1e1"
REFERENCES = {
    f"BabelCDB-{DB_SHA}-cards.cdb": (
        f"https://raw.githubusercontent.com/ProjectIgnis/BabelCDB/{DB_SHA}/cards.cdb",
        "cbc868862e257745a97e7139d791ae0a96c7a7c10ac4370bc67b200de60506b2"),
    f"BabelCDB-{DB_SHA}-README.md": (
        f"https://raw.githubusercontent.com/ProjectIgnis/BabelCDB/{DB_SHA}/README.md",
        "dcb692eb565ce970f21ff4fb424f9370b52d8dd72edf107437a69289a5fb2b4a"),
    f"CardScripts-{SCRIPTS_SHA}.zip": (
        f"https://codeload.github.com/ProjectIgnis/CardScripts/zip/{SCRIPTS_SHA}",
        "72e4cb87d41ed2a9d174bb631155e8d64c421af901a2528739cb376701312842"),
}
NAME_ONLY = {10855: "Number 94: Crystalzero", 11766: "Number S39: Utopia the Lightning"}
REVIEWED_REMAPS = {
    4998: (10000000, "Obelisk the Tormentor", 33, 10, 4000, 4000),
    4999: (10000020, "Slifer the Sky Dragon", 33, 10, -2, -2),
    5000: (10000010, "The Winged Dragon of Ra", 33, 10, -2, -2),
    11927: (10000080, "The Winged Dragon of Ra - Sphere Mode", 33, 10, -2, -2),
    12234: (10000090, "The Winged Dragon of Ra - Immortal Phoenix", 33554465, 10, 4000, 4000),
    10855: (62070231, "Number 94: Crystalzero", 8388641, 5, 2200, 1600),
    11766: (56832966, "Number S39: Utopia the Lightning", 8388641, 5, 2500, 2000),
}
REVIEWED_SCRIPT_OVERRIDES = {88264978: "pre-errata/c88264978.lua"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def prepare_references(directory, fetch):
    directory.mkdir(parents=True, exist_ok=True)
    result = {}
    for name, (url, expected) in REFERENCES.items():
        path = directory / name
        if not path.exists() and fetch:
            with urllib.request.urlopen(url, timeout=120) as response:
                data = response.read()
            require(hashlib.sha256(data).hexdigest() == expected, f"Downloaded reference digest mismatch: {name}")
            path.write_bytes(data)
        require(path.is_file(), f"Missing reference {path}; run with --fetch")
        require(digest(path) == expected, f"Local reference digest mismatch: {name}")
        result[name] = {"url": url, "sha256": expected, "bytes": path.stat().st_size}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--references", type=Path, default=ROOT / "outputs/ocg-reference")
    parser.add_argument("--obb", type=Path, default=ROOT / "com.konami.ygodgtest/main.116.com.konami.ygodgtest.obb")
    parser.add_argument("--report", type=Path, default=PROJECT / "GeneratedData/ocg-coverage.json")
    parser.add_argument("--fetch", action="store_true")
    args = parser.parse_args()
    references = prepare_references(args.references, args.fetch)
    db_path = args.references / f"BabelCDB-{DB_SHA}-cards.cdb"
    with sqlite3.connect(db_path.resolve().as_uri() + "?mode=ro", uri=True) as connection:
        connection.row_factory = sqlite3.Row
        db = {row["id"]: dict(row) for row in connection.execute(
            "SELECT datas.*, texts.name, texts.desc FROM datas JOIN texts USING(id)")}
        require(connection.execute("PRAGMA integrity_check").fetchone()[0] == "ok", "SQLite integrity check failed")
    require(db[89631139]["name"] == "Blue-Eyes White Dragon", "Expected English database")

    generated = PROJECT / "GeneratedData"
    texts = {row["sourceIndex"]: row for row in load(generated / "cards-en.json")}
    metadata = load(generated / "card-index.json")[1:]
    decks = load(generated / "ydc-decks.json")
    require(len(metadata) == len(texts) == 7580 and len(decks) == 799, "Unexpected source dataset")
    by_konami = {row["propFirst"] & 0x3FFF: row for row in metadata}
    require(len(by_konami) == len(metadata), "Duplicate Konami IDs")
    nonzero = [row["password"] for row in metadata if row["password"]]
    require(len(nonzero) == len(set(nonzero)), "Duplicate nonzero OBB passwords need explicit handling")
    names_index = defaultdict(list)
    for row in db.values():
        names_index[row["name"]].append(row)

    with zipfile.ZipFile(args.references / f"CardScripts-{SCRIPTS_SHA}.zip") as archive:
        prefix = f"CardScripts-{SCRIPTS_SHA}/"
        script_bytes = {item.filename[len(prefix):]: archive.read(item)
                        for item in archive.infolist() if item.filename.startswith(prefix) and item.filename.endswith(".lua")}
        scripts = {path: data.decode("utf-8-sig") for path, data in script_bytes.items()}
        readme = archive.read(prefix + "README.md").decode("utf-8-sig")
        license_bytes = archive.read(prefix + "COPYING")
    require("GNU Affero General Public License" in readme and "any later version" in readme, "Script license changed")
    script_by_basename = defaultdict(list)
    for path in sorted(scripts):
        script_by_basename[Path(path).name].append(path)

    def script_status(code, row):
        filename = f"c{code}.lua"
        official = "official/" + filename
        if official in scripts:
            return {"status": "directOfficial", "path": official}
        if code in REVIEWED_SCRIPT_OVERRIDES:
            path = REVIEWED_SCRIPT_OVERRIDES[code]
            require(path in scripts, "Reviewed script override missing from pinned archive")
            return {"status": "reviewedPreErrata", "path": path,
                    "sha256": hashlib.sha256(script_bytes[path]).hexdigest(),
                    "eraNote": "Explicit exact-code lookup under pre-errata, not a generic folder fallback; current CDB text/older APK behavior may differ"}
        # Only plain Normal/Tuner monsters need no per-card effect or summoning procedure script.
        if row["type"] in (0x11, 0x1011):
            return {"status": "scriptlessNormal", "type": row["type"]}
        if row["type"] & 0x4000:
            return {"status": "tokenDefinitionCreatedByEffect", "type": row["type"]}
        return {"status": "missingOfficialScript", "otherFolderCandidates": script_by_basename.get(filename, [])}

    require(script_status(89631139, db[89631139])["status"] == "scriptlessNormal",
            "Scriptless Normal classification regression")
    require(script_status(45231177, db[45231177])["status"] == "directOfficial",
            "Non-effect Fusion monsters still require a summoning script")

    mapping = {}
    rows = []
    zero_password = []
    missing_password = []
    name_changes = []
    stat_changes = []
    aliases = []
    script_counts = Counter()
    text_differences = 0
    with zipfile.ZipFile(args.obb) as obb:
        source_decks = {Path(info.filename).name: info.filename for info in obb.infolist()
                        if info.filename.endswith(".ydc")}
        require(len(source_decks) == len(decks) == len({deck["file"] for deck in decks}),
                "Source/generated deck set mismatch")
        for deck in decks:
            require(encode_ydc(deck) == obb.read(source_decks[deck["file"]]),
                    f"Generated deck differs from raw OBB: {deck['file']}")
        prop = obb.read("assets/CARD_Prop.bin")
        passwords = obb.read("assets/CARD_Pass.bin")
        offsets = obb.read("assets/CARD_Indx_E.bin")
        name_blob = obb.read("assets/CARD_Name_E.bin")
        desc_blob = obb.read("assets/CARD_Desc_E.bin")
        require(len(prop) == (len(metadata) + 1) * 8 and len(passwords) == (len(metadata) + 1) * 4
                and len(offsets) == (len(metadata) + 2) * 8, "OBB/generated table dimensions differ")
        images = {}
        for info in obb.infolist():
            if info.filename.endswith(".jpg") and Path(info.filename).stem.isdecimal():
                images[int(Path(info.filename).stem)] = info
        image_mappings = []
        for source in metadata:
            kid = source["propFirst"] & 0x3FFF
            code = source["password"]
            text = texts[source["sourceIndex"]]
            index = source["sourceIndex"]
            first, second = struct.unpack_from("<II", prop, index * 8)
            name_offset, desc_offset = struct.unpack_from("<II", offsets, index * 8)
            require(first == source["propFirst"] and second == source["propSecond"]
                    and code == struct.unpack_from("<I", passwords, index * 4)[0]
                    and text["name"] == text_at(name_blob, name_offset)
                    and text["description"] == text_at(desc_blob, desc_offset),
                    f"Generated card {kid} does not match raw OBB")
            if not code:
                candidates = sorted(names_index[text["name"]], key=lambda row: row["id"])
                canonical = [row for row in candidates if row["alias"] == 0]
                zero_password.append({"konamiID": kid, "name": text["name"], "kindCode": source["kindCode"],
                                      "reason": "password0Token" if source["kindCode"] == 10 else "password0Monster",
                                      "canonicalNameCandidate": canonical[0]["id"] if len(canonical) == 1 else None,
                                      "candidates": [{"code": row["id"], "alias": row["alias"], "type": row["type"],
                                                      "script": script_status(row["id"], row)} for row in candidates],
                                      "automaticMappingAccepted": False})
                continue
            if code not in db:
                missing_password.append({"konamiID": kid, "code": code, "name": text["name"]})
                continue
            core = db[code]
            mapping[str(kid)] = code
            status = script_status(code, core)
            script_counts[status["status"]] += 1
            rows.append({"konamiID": kid, "code": code, "name": text["name"], "coreName": core["name"],
                         "script": status})
            if text["name"] != core["name"]:
                name_changes.append({"konamiID": kid, "code": code, "obb": text["name"], "database": core["name"]})
            if " ".join(text["description"].split()) != " ".join(core["desc"].split()):
                text_differences += 1
            differences = {}
            if core["type"] & 1:
                for field in ("atk", "def", "level"):
                    left = source[field] if source[field] is not None else -2
                    right = (core[field] & 255) if field == "level" else core[field]
                    if left != right:
                        differences[field] = {"obb": left, "database": right}
            if differences:
                stat_changes.append({"konamiID": kid, "code": code, "differences": differences})
            if core["alias"]:
                aliases.append({"konamiID": kid, "code": code, "alias": core["alias"],
                                "aliasPresent": core["alias"] in db,
                                "kind": "alternateArtwork" if abs(core["alias"] - code) <= 10 else "sameNameRule",
                                "codeCollapsedToAlias": False})
            info = images.get(kid)
            image_mappings.append({"konamiID": kid, "coreCode": code,
                                   "obbPath": info.filename if info else None,
                                   "coreImageFilename": f"{code}.jpg",
                                   "bytes": info.file_size if info else None,
                                   "crc32": f"{info.CRC:08x}" if info else None})

    password_mapping = dict(mapping)
    reviewed_remaps = []
    for kid, (code, name, card_type, level, attack, defense) in REVIEWED_REMAPS.items():
        canonical = [row for row in names_index[name] if row["alias"] == 0]
        require(len(canonical) == 1 and canonical[0]["id"] == code, f"Reviewed exact-name mapping changed: {kid}")
        core = db[code]
        require((core["type"], core["level"] & 255, core["atk"], core["def"]) ==
                (card_type, level, attack, defense), f"Reviewed supplemental metadata changed: {kid}")
        source = by_konami.get(kid)
        if source is not None:
            require(source["password"] == 0 and texts[source["sourceIndex"]]["name"] == name,
                    f"Reviewed zero-password identity changed: {kid}")
            require((source["level"], source["atk"] if source["atk"] is not None else -2,
                     source["def"] if source["def"] is not None else -2) == (level, attack, defense),
                    f"Reviewed OBB stats disagree: {kid}")
            require(source["kindCode"] == (27 if kid == 12234 else 1), "Reviewed God-card kind differs")
        else:
            require(NAME_ONLY.get(kid) == name, f"Unapproved supplemental card: {kid}")
        require(code not in mapping.values(), f"Reviewed remap would collapse existing code: {kid}")
        mapping[str(kid)] = code
        reviewed_remaps.append({"konamiID": kid, "coreCode": code, "name": name,
                                "method": "explicitReviewedRemap", "sourceNameMatch": True,
                                "sourceNameSource": "rawOBB" if source is not None else "verifiedNameOnlyMapping",
                                "uniqueCanonicalNameCandidate": True, "nativeDataMissing": source is None,
                                "sourcePasswordZero": source is not None, "obbStatsAndKindMatch": True if source is not None else None,
                                "cdbMetadata": {key: core[key] for key in ("type", "atk", "def", "level", "race", "attribute")},
                                "script": script_status(code, core),
                                "provenance": f"https://github.com/ProjectIgnis/BabelCDB/blob/{DB_SHA}/cards.cdb",
                                "note": "User chose EDOPro + OBB; explicit mapping reviewed in this session, no fabricated OBB definition"})
        info = images.get(kid)
        image_mappings.append({"konamiID": kid, "coreCode": code, "obbPath": info.filename if info else None,
                               "coreImageFilename": f"{code}.jpg", "bytes": info.file_size if info else None,
                               "crc32": f"{info.CRC:08x}" if info else None})

    deck_mappings = []
    used = set()
    for deck in decks:
        item = {"file": deck["file"], "unknownHeader": deck["unknown"], "sourceKonamiIDs": {}, "coreCodes": {}, "unresolved": []}
        for zone in ("main", "extra", "side"):
            item["sourceKonamiIDs"][zone] = deck[zone]
            item["coreCodes"][zone] = [mapping.get(str(kid)) for kid in deck[zone]]
            for index, kid in enumerate(deck[zone]):
                used.add(kid)
                if str(kid) not in mapping:
                    item["unresolved"].append({"zone": zone, "index": index, "konamiID": kid,
                                               "reason": "password0" if kid in by_konami else "noOBBDefinition"})
        item["passwordMappingComplete"] = all(str(kid) in password_mapping for zone in ("main", "extra", "side") for kid in deck[zone])
        item["mappingComplete"] = not item["unresolved"]
        deck_mappings.append(item)

    # Scan literal loader dependencies; dynamic loader behavior still needs the matching ocgcore and execution.
    roots = sorted(path for path in scripts if "/" not in path)
    queue = roots + [row["script"]["path"] for row in rows + reviewed_remaps if "path" in row["script"]]
    visited = set()
    literal_dependencies = []
    unresolved_loads = []
    constants = dict(re.findall(r"\b(CARD_[A-Z_]+)\s*=\s*(\d+)\b", scripts["constant.lua"]))
    loaders = re.compile(r"Duel\.(LoadScript|LoadCardScript|LoadCardScriptAlias)\s*\(([^)\n]+)\)")
    while queue:
        path = queue.pop()
        if path in visited:
            continue
        visited.add(path)
        for line_number, line in enumerate(scripts[path].splitlines(), 1):
            if line.lstrip().startswith("--"):
                continue
            for method, expression in loaders.findall(line):
                expression = expression.strip()
                match = re.fullmatch(r"[\"']([^\"']+)[\"']", expression)
                target = match.group(1) if match else None
                if method == "LoadCardScriptAlias" and target is None:
                    code = expression if expression.isdecimal() else constants.get(expression)
                    if code:
                        target = f"c{code}.lua"
                if target is None:
                    unresolved_loads.append({"source": path, "line": line_number, "expression": expression,
                                             "reason": "dynamicExpression"})
                    continue
                options = ([target] if target in scripts else
                           ["official/" + target] if "official/" + target in scripts else script_by_basename.get(target, []))
                dependency = {"source": path, "target": target, "candidates": options}
                literal_dependencies.append(dependency)
                if len(options) == 1:
                    queue.append(options[0])
                else:
                    unresolved_loads.append({**dependency, "reason": "ambiguousOrMissingPath"})

    unresolved_deck_ids = sorted(kid for kid in used if str(kid) not in mapping)
    report = {
        "auditCompleted": True, "runtimeVerified": False, "built": False, "fullGameReady": False,
        "sources": {
            "OBB": {"sha256": digest(args.obb), "bytes": args.obb.stat().st_size,
                    "generatedCatalogComparedToRaw": True, "sourceDecksByteExact": True},
            "BabelCDB": {"repository": "https://github.com/ProjectIgnis/BabelCDB", "commit": DB_SHA,
                         "database": "cards.cdb", "language": "English", "rows": len(db),
                         "license": "No explicit license found in repository root metadata/README; redistribution terms unresolved"},
            "CardScripts": {"repository": "https://github.com/ProjectIgnis/CardScripts", "commit": SCRIPTS_SHA,
                            "license": "AGPL-3.0-or-later", "licenseFile": "COPYING",
                            "licenseSHA256": hashlib.sha256(license_bytes).hexdigest(), "luaFiles": len(scripts),
                            "targetRuntimeFromREADME": "Lua 5.3 in edo9300/ygopro-core"},
            "downloads": references,
        },
        "summary": {"obbCards": len(metadata), "nonzeroPasswords": len(nonzero), "matchedByPassword": len(rows),
                    "missingNonzeroPasswords": len(missing_password), "zeroPasswords": len(zero_password),
                    "zeroPasswordTokens": sum(row["kindCode"] == 10 for row in zero_password),
                    "unmappedTokenIDsUsedInDecks": sorted(row["konamiID"] for row in zero_password if row["kindCode"] == 10 and row["konamiID"] in used),
                    "exactEnglishNameMatches": len(rows) - len(name_changes), "nameDifferences": len(name_changes),
                    "monsterStatDifferences": len(stat_changes), "descriptionTextDifferences": text_differences,
                    "scriptCoverage": dict(script_counts), "decks": len(decks), "uniqueDeckKonamiIDs": len(used),
                    "passwordMappedDeckIDs": sum(str(kid) in password_mapping for kid in used),
                    "reviewedRemappedDeckIDs": sorted(kid for kid in used if kid in REVIEWED_REMAPS),
                    "mappedDeckIDsAfterReview": len(used) - len(unresolved_deck_ids),
                    "unresolvedDeckIDs": unresolved_deck_ids,
                    "decksWithCompletePasswordMapping": sum(deck["passwordMappingComplete"] for deck in deck_mappings),
                    "decksWithCompleteReviewedMapping": sum(deck["mappingComplete"] for deck in deck_mappings),
                    "imageMappings": len(image_mappings), "missingImages": sum(row["obbPath"] is None for row in image_mappings)},
        "metadataDifferences": {"names": name_changes, "stats": stat_changes,
                                "descriptionNote": "Whitespace-normalized text difference is not proof of an erratum; current EDOPro rules/text may differ from this old APK"},
        "aliases": aliases, "missingPasswords": missing_password,
        "missingOfficialScripts": [row for row in rows if row["script"]["status"] in ("missingOfficialScript", "reviewedPreErrata")],
        "scriptDependencies": {"rootLibraries": roots, "staticClosureFiles": len(visited),
                               "literalLoads": sorted(literal_dependencies, key=lambda row: (row["source"], row["target"])),
                               "unresolvedLoads": sorted(unresolved_loads, key=lambda row: (row["source"], row.get("line", 0))),
                               "runtimeClosureProven": False,
                               "note": "All folders are preserved in reference ZIP. Only the explicit exact-code override is accepted; there is no generic pre-errata/unofficial fallback."},
        "sourceMetadataWarnings": ["OBB generated race labels for God cards say Cyberse for raceCode23; this is a known cross-era enum labeling error. EDOPro data supplies its own race bitmask; no OBB bytes were changed."],
        "bridge": {"konamiToCoreCode": mapping, "unresolved": [row for row in zero_password if row["konamiID"] not in REVIEWED_REMAPS],
                   "reviewedRemaps": reviewed_remaps, "scriptOverrides": REVIEWED_SCRIPT_OVERRIDES,
                   "deckMappings": deck_mappings, "imageMappings": image_mappings,
                   "policy": "Direct nonzero password matches plus seven explicit reviewed remaps. Remaining null codes must block export/play. Never use code0, fuzzy names, or generic pre-errata fallback."},
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["summary"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
