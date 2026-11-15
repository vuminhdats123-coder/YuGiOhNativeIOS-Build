"""Validate practice decks against the supplied OBB without compiling the iOS app."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import struct
import zipfile

PROJECT = Path(__file__).resolve().parents[1]
ROOT = PROJECT.parent
GENERATED = PROJECT / "GeneratedData"
EFFECTS = {
    4844: (55144522, 13, "Pot of Greed"),
    4349: (76103675, 13, "Sparks"),
    4348: (84257639, 13, "Dian Keto the Cure Master"),
    4861: (41420027, 14, "Solemn Judgment"),
    4842: (83764718, 13, "Monster Reborn"),
    11740: (911883, 13, "Unexpected Dai"),
    4343: (12580477, 13, "Raigeki"),
    4342: (53129443, 13, "Dark Hole"),
}
DEFERRED = {4909: (5318639, 13, "Mystical Space Typhoon")}
NAME_ONLY = {
    10855: "Number 94: Crystalzero",
    11766: "Number S39: Utopia the Lightning",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"), object_pairs_hook=unique_object)


def uint(value, bits, label):
    require(type(value) is int and 0 <= value < (1 << bits), f"Invalid {label}: {value!r}")
    return value


def text_at(blob, offset):
    require(type(offset) is int and offset % 2 == 0 and 0 <= offset < len(blob),
            f"Invalid UTF-16 offset {offset}")
    for end in range(offset, len(blob) - 1, 2):
        if blob[end:end + 2] == b"\0\0":
            return blob[offset:end].decode("utf-16le", errors="strict").strip()
    raise ValueError(f"Unterminated UTF-16 text at {offset}")


def encode_ydc(deck):
    require(set(deck) == {"file", "unknown", "main", "extra", "side"}, "Unexpected YDC JSON fields")
    require(type(deck["file"]) is str and Path(deck["file"]).name == deck["file"], "Invalid YDC filename")
    data = struct.pack("<Q", uint(deck["unknown"], 64, "header"))
    for group in ("main", "extra", "side"):
        cards = deck[group]
        require(type(cards) is list, f"{deck['file']}: {group} must be an array")
        data += struct.pack("<H", uint(len(cards), 16, "count"))
        for card in cards:
            data += struct.pack("<H", uint(card, 16, "card ID"))
    return data


def supported(row):
    kid = row["propFirst"] & 0x3FFF
    if kid in EFFECTS:
        password, kind, _ = EFFECTS[kid]
        return row["password"] == password and row["kindCode"] == kind
    return (row["kindCode"] == 0 and 1 <= row["level"] <= 8
            and type(row["atk"]) is int and type(row["def"]) is int)


def self_check():
    # The null byte at the end of ASCII plus U+0100's first byte is not a terminator.
    assert text_at("A\u0100B\0".encode("utf-16le"), 0) == "A\u0100B"
    try:
        text_at(b"A\0", 0)
    except ValueError:
        pass
    else:
        raise AssertionError("Unterminated strings must fail")
    assert encode_ydc({"file": "empty.ydc", "unknown": 0, "main": [], "extra": [], "side": []}) == bytes(14)
    for value in (-1, 65536, True, "4007"):
        try:
            encode_ydc({"file": "bad.ydc", "unknown": 0, "main": [value], "extra": [], "side": []})
        except ValueError:
            pass
        else:
            raise AssertionError("Out-of-range/non-integer card IDs must fail")


def validate(obb):
    cards = load_json(GENERATED / "cards-en.json")
    metadata = load_json(GENERATED / "card-index.json")
    names = load_json(GENERATED / "card-id-names.json")
    decks = load_json(GENERATED / "ydc-decks.json")
    practice = load_json(GENERATED / "offline-practice-decks.json")
    require(type(cards) is list and type(metadata) is list and type(names) is dict,
            "Invalid card catalog schema")
    require(cards == load_json(PROJECT / "Resources/cards_en.json"), "Bundled and generated card text differ")
    require(metadata == load_json(PROJECT / "Resources/card-index.json"), "Bundled and generated metadata differ")
    text_by_index = {}
    for row in cards:
        require(set(row) == {"id", "sourceIndex", "name", "description"}, "Unexpected card text fields")
        index = uint(row["sourceIndex"], 16, "sourceIndex")
        require(row["id"] == index and index not in text_by_index, "Duplicate/misaligned internal card ID")
        require(type(row["name"]) is str and row["name"] and type(row["description"]) is str,
                "Invalid card text")
        text_by_index[index] = row

    with zipfile.ZipFile(obb) as archive:
        prop = archive.read("assets/CARD_Prop.bin")
        genre = archive.read("assets/CARD_Genre.bin")
        passwords = archive.read("assets/CARD_Pass.bin")
        offsets = archive.read("assets/CARD_Indx_E.bin")
        name_blob = archive.read("assets/CARD_Name_E.bin")
        desc_blob = archive.read("assets/CARD_Desc_E.bin")
        int_ids = archive.read("assets/CARD_IntID.bin")
        require(len(prop) % 8 == 0 and len(genre) == len(prop), "Invalid Prop/Genre dimensions")
        count = len(prop) // 8
        require(len(passwords) == count * 4 and len(offsets) == (count + 1) * 8,
                "Invalid password/text dimensions")
        require(len(metadata) == count and len(cards) == count - 1, "Missing catalog records")
        by_konami = {}
        for i, row in enumerate(metadata):
            first, second = struct.unpack_from("<II", prop, i * 8)
            require(row["sourceIndex"] == i and row["intID"] == i, f"Internal ID mismatch at {i}")
            expected = {
                "propFirst": first, "propSecond": second,
                "kindCode": (second >> 1) & 63, "attributeCode": (second >> 7) & 15,
                "level": (second >> 11) & 15, "spellTrapIcon": (second >> 15) & 7,
                "raceCode": (second >> 18) & 31, "scaleLeft": (second >> 23) & 15,
                "scaleRight": (second >> 27) & 15,
                "genreMask": struct.unpack_from("<Q", genre, i * 8)[0],
                "password": struct.unpack_from("<I", passwords, i * 4)[0],
            }
            for field, value in expected.items():
                require(type(row.get(field)) is int and row[field] == value, f"Metadata mismatch {i}/{field}")
            for field, raw in (("atk", (first >> 14) & 511), ("def", (first >> 23) & 511)):
                require(row[field] == (None if raw == 511 else raw * 10), f"Stat mismatch {i}/{field}")
            name_offset, desc_offset = struct.unpack_from("<II", offsets, i * 8)
            name, description = text_at(name_blob, name_offset), text_at(desc_blob, desc_offset)
            if i == 0:
                require(first == second == 0 and name == description == "", "Invalid empty card record")
                continue
            require(text_by_index[i]["name"] == name and text_by_index[i]["description"] == description,
                    f"Text mismatch at internal ID {i}")
            kid = first & 0x3FFF
            require(kid not in by_konami, f"Duplicate Konami ID {kid}")
            require(names.get(str(kid)) == name, f"Name-map mismatch for Konami ID {kid}")
            offset = (kid - 3900) * 2
            require(0 <= offset < len(int_ids) and struct.unpack_from("<H", int_ids, offset)[0] == i,
                    f"IntID/Prop mismatch for {kid}")
            by_konami[kid] = row

        extras = {int(key): value for key, value in names.items() if int(key) not in by_konami}
        require(extras == NAME_ONLY, "Unexpected name-only fallback mappings")
        for kid in NAME_ONLY:
            require(struct.unpack_from("<H", int_ids, (kid - 3900) * 2)[0] == 0,
                    f"Fallback {kid} now has native data; reassess support")
        for kid, (password, kind, name) in (EFFECTS | DEFERRED).items():
            row = by_konami[kid]
            require(row["password"] == password and row["kindCode"] == kind and names[str(kid)] == name,
                    f"Effect identity mismatch for {kid}")

        require(type(decks) is list and len(decks) == 799, "Expected 799 source decks")
        source_ydc = {Path(info.filename).name: info.filename for info in archive.infolist()
                      if info.filename.endswith(".ydc")}
        require(len(source_ydc) == len(decks) and len({d["file"] for d in decks}) == len(decks),
                "Duplicate/missing source deck filename")
        used = set()
        for deck in decks:
            require(deck["file"] in source_ydc, f"Unknown source deck {deck['file']}")
            require(encode_ydc(deck) == archive.read(source_ydc[deck["file"]]),
                    f"Byte round trip mismatch: {deck['file']}")
            used.update(card for group in ("main", "extra", "side") for card in deck[group])
        require(all(str(kid) in names for kid in used), "Source deck card without a display name")

    require(type(practice) is list and len(practice) == 2, "Exactly two practice decks required")
    practice_summary = []
    for deck in practice:
        require(set(deck) == {"file", "main", "extra", "side"}, "Invalid practice deck schema")
        require(type(deck["file"]) is str and deck["file"], "Practice deck needs a name")
        require(type(deck["main"]) is list and len(deck["main"]) == 40 and deck["extra"] == deck["side"] == [],
                "Practice deck must contain 40 Main cards and empty Extra/Side")
        copies = Counter(deck["main"])
        require(max(copies.values()) <= 3, "Practice deck exceeds three copies")
        for kid in deck["main"]:
            uint(kid, 16, "practice card")
            require(kid in by_konami and supported(by_konami[kid]), f"Unsupported practice card {kid}")
        require(set(EFFECTS) <= set(copies), "Each practice deck must include all eight supported effects")
        normal_count = sum(copies[kid] for kid in copies if by_konami[kid]["kindCode"] == 0)
        require(normal_count >= 24, "Each practice deck needs at least 24 Normal Monsters")
        require(any(by_konami[kid]["kindCode"] == 0 and 5 <= by_konami[kid]["level"] <= 6 for kid in copies)
                and any(by_konami[kid]["kindCode"] == 0 and 7 <= by_konami[kid]["level"] <= 8 for kid in copies),
                "Each practice deck needs one- and two-Tribute Normal Monsters")
        practice_summary.append({"name": deck["file"], "cards": 40, "uniqueCards": len(copies),
                                 "maxCopies": max(copies.values()), "normalMonsters": normal_count,
                                 "contents": [{"konamiID": kid, "name": names[str(kid)], "copies": copies[kid]}
                                              for kid in copies]})
    require(practice[0]["file"] != practice[1]["file"] and practice[0]["main"] != practice[1]["main"],
            "Practice decks must be distinct")
    with obb.open("rb") as source:
        source_hash = hashlib.file_digest(source, "sha256").hexdigest()
    return {
        "valid": True,
        "scope": "Raw OBB/card metadata/name mapping/YDC byte round trips/practice-deck data; not a game completion check",
        "sourceOBBSHA256": source_hash,
        "catalogCards": len(cards), "metadataRecordsIncludingEmpty": count,
        "generatedAndResourceCatalogsEqual": True,
        "allCatalogNamesAndDescriptionsMatchOBB": True,
        "allPropGenrePasswordValuesMatchOBB": True,
        "allIntIDMappingsMatchProp": True,
        "ydcByteExactRoundTrips": len(decks), "uniqueDeckKonamiIDs": len(used),
        "sourceBackedDeckIDs": len(used & set(by_konami)),
        "nameOnlyNotPlayable": [{"konamiID": kid, "name": name, "nativeDefinitionAvailable": False}
                                for kid, name in NAME_ONLY.items()],
        "supportedEffectIdentities": [{"konamiID": kid, "name": name, "password": f"{password:08d}",
                                       "sourceDescription": text_by_index[by_konami[kid]["sourceIndex"]]["description"]}
                                      for kid, (password, _, name) in EFFECTS.items()],
        "deferredEffectIdentities": [{"konamiID": kid, "name": name, "password": f"{password:08d}",
                                      "reason": "Quick-Play timing and destruction of active chain sources are not supported"}
                                     for kid, (password, _, name) in DEFERRED.items()],
        "practiceDecks": practice_summary,
        "engineBehaviorTestsExecuted": False,
        "iosBuildExecuted": False,
        "portComplete": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--obb", type=Path, default=ROOT / "com.konami.ygodgtest/main.116.com.konami.ygodgtest.obb")
    parser.add_argument("--report", type=Path, default=GENERATED / "duel-data-validation.json")
    args = parser.parse_args()
    self_check()
    try:
        report = validate(args.obb)
    except (ValueError, KeyError, TypeError, OSError, struct.error, zipfile.BadZipFile) as error:
        report = {"valid": False, "error": str(error), "iosBuildExecuted": False, "portComplete": False}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in report.items() if key != "practiceDecks"}, ensure_ascii=False))
    raise SystemExit(0 if report["valid"] else 1)


if __name__ == "__main__":
    main()
