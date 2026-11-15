"""Prepare an offline EDOPro data directory; never compile or modify source archives."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import logging
import re
from pathlib import Path, PurePosixPath
import shutil
import sqlite3
import stat
import struct
import subprocess
import uuid
import zipfile

BASE_DIRS = ("config", "fonts", "textures", "skin", "sound", "lflists")
TEXTURES = ("cover", "unknown", "act", "attack", "chain", "negated", "number", "lp", "lpf",
            "mask", "equip", "target", "chaintarget", "lim", "ot", "f1", "f2", "f3", "bg", "settings")
TEXTURES += tuple(f"{prefix}{suffix}" for prefix in ("field", "field-transparent", "fieldSP", "field-transparentSP")
                  for suffix in ("", "2", "3", "4"))
EXTRA_TYPES = 0x40 | 0x2000 | 0x800000 | 0x4000000


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def safe_relative(name: str) -> Path:
    value = PurePosixPath(name)
    if not name or "\\" in name or ":" in name or "\0" in name or value.is_absolute() or ".." in value.parts:
        raise ValueError(f"Unsafe asset path: {name!r}")
    return Path(*value.parts)


def archive_entries(archive: zipfile.ZipFile) -> dict[str, zipfile.ZipInfo]:
    entries, seen = {}, set()
    for info in archive.infolist():
        key = safe_relative(info.filename).as_posix().casefold()
        if key in seen or stat.S_ISLNK(info.external_attr >> 16):
            raise ValueError(f"Duplicate or symbolic-link archive entry: {info.filename}")
        seen.add(key)
        if not info.is_dir():
            entries[info.filename] = info
    return entries


def decode_deck(data: bytes) -> dict:
    if len(data) < 14:
        raise ValueError("Truncated YDC header")
    result = {"unknownHeader": struct.unpack_from("<Q", data)[0]}
    offset = 8
    for group in ("main", "extra", "side"):
        if offset + 2 > len(data):
            raise ValueError(f"Truncated {group} count")
        count = struct.unpack_from("<H", data, offset)[0]
        offset += 2
        if offset + count * 2 > len(data):
            raise ValueError(f"Truncated {group} cards")
        result[group] = list(struct.unpack_from(f"<{count}H", data, offset))
        offset += count * 2
    if offset != len(data):
        raise ValueError("Trailing YDC bytes")
    return result


def deck_problems(deck: dict, database: dict[int, tuple[int, int, str]]) -> list[str]:
    problems = []
    if not 40 <= len(deck["main"]) <= 60:
        problems.append("Main count is outside 40–60 (source may be a pack/support list)")
    if len(deck["extra"]) > 15 or len(deck["side"]) > 15:
        problems.append("Extra/Side count exceeds 15")
    for zone in ("main", "extra", "side"):
        for code in deck[zone]:
            card_type = database[code][0]
            if card_type & 0x4000:
                problems.append(f"Token {code} cannot be in a deck")
            if zone == "main" and card_type & EXTRA_TYPES:
                problems.append(f"Extra Deck monster {code} is in Main")
            if zone == "extra" and not card_type & EXTRA_TYPES:
                problems.append(f"Non-Extra monster {code} is in Extra")
    aliases = [database[code][1] or code for zone in ("main", "extra", "side") for code in deck[zone]]
    problems += [f"More than three copies of {code}" for code, count in Counter(aliases).items() if count > 3]
    return sorted(set(problems))


def write_ydk(path: Path, deck: dict) -> None:
    lines = ["#created from supplied OBB; see reports/decks.json", "#main"]
    lines += list(map(str, deck["main"])) + ["#extra"] + list(map(str, deck["extra"]))
    lines += ["!side"] + list(map(str, deck["side"]))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def client_deck_filename(source: str) -> str:
    # EDOPro's deck dropdown scans only the deck root; retain origin in the report and a stable suffix.
    stem = re.sub(r"[^A-Za-z0-9_-]+", "_", PurePosixPath(source).stem).strip("_")[:100] or "deck"
    suffix = hashlib.sha256(source.encode("utf-8")).hexdigest()[:10]
    return f"OBB_{stem}_{suffix}.ydk"


def copy_file(source: Path, target: Path) -> None:
    if source.is_symlink() or getattr(source, "is_junction", lambda: False)():
        raise ValueError(f"Linked source assets are not allowed: {source}")
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)


def copy_tree(source: Path, target: Path) -> None:
    for item in sorted(source.rglob("*")):
        if item.is_symlink() or getattr(item, "is_junction", lambda: False)():
            raise ValueError(f"Linked source assets are not allowed: {item}")
        if item.is_file():
            copy_file(item, target / safe_relative(item.relative_to(source).as_posix()))


def prepare(obb: Path, cdb: Path, scripts: Path, base_assets: Path, audit_path: Path,
            output: Path, reviewed_mappings: Path | None = None, source_lock: Path | None = None,
            include_vi: bool = False, offline_ai: Path | None = None) -> dict:
    obb, cdb, scripts, base_assets, audit_path, output = map(Path.resolve,
        (obb, cdb, scripts, base_assets, audit_path, output))
    if output.exists():
        raise FileExistsError(f"Refusing to replace existing asset directory: {output}")
    if any(output == source or output in source.parents or source in output.parents
           for source in (obb, cdb, scripts, base_assets, audit_path)):
        raise ValueError("Output must be separate from source assets")
    audit = json.loads(audit_path.read_text(encoding="utf-8"))
    if digest(obb) != audit["sources"]["OBB"]["sha256"]:
        raise ValueError("OBB hash differs from mapping audit")
    downloads = audit["sources"]["downloads"]
    cdb_hashes = {item["sha256"] for name, item in downloads.items() if name.endswith(".cdb")}
    if digest(cdb) not in cdb_hashes:
        raise ValueError("CDB hash differs from pinned mapping audit")
    if source_lock:
        lock = json.loads(source_lock.read_text(encoding="utf-8"))
        if lock["database"]["sha256"] != digest(cdb) or lock["sourceOBB"]["sha256"] != digest(obb):
            raise ValueError("Source lock and asset hashes disagree")
        if scripts.is_file() and lock["scripts"]["archiveSHA256"] != digest(scripts):
            raise ValueError("Source lock and script archive disagree")
        commit = subprocess.check_output(["git", "-C", str(base_assets), "rev-parse", "HEAD"], text=True).strip()
        if commit != lock["distribution"]["commit"]:
            raise ValueError("Distribution assets differ from source lock")
    connection = sqlite3.connect(cdb.as_uri() + "?mode=ro", uri=True)
    try:
        database = {code: (kind, alias, name) for code, kind, alias, name in connection.execute(
            "SELECT datas.id, datas.type, datas.alias, texts.name FROM datas JOIN texts ON texts.id = datas.id")}
    finally:
        connection.close()
    mapping = {int(key): value for key, value in audit["bridge"]["konamiToCoreCode"].items()}
    if any(type(code) is not int or code not in database for code in mapping.values()):
        raise ValueError("Audited mapping points outside the pinned database")
    overrides = audit["bridge"].get("reviewedRemaps", [])
    if reviewed_mappings:
        additional = json.loads(reviewed_mappings.read_text(encoding="utf-8"))["entries"]
        overrides = overrides + additional
        seen = set()
        for row in additional:
            kid, code = row["konamiID"], row["coreCode"]
            if (type(kid) is not int or type(code) is not int or kid in seen or code not in database
                    or not row.get("evidence") or row.get("name") != database[code][2]):
                raise ValueError("Invalid reviewed mapping or canonical name")
            if kid in mapping and mapping[kid] != code:
                raise ValueError("Reviewed mapping cannot replace a verified password")
            mapping[kid] = code
            seen.add(kid)

    missing = [name for name in ("config/strings.conf", "config/configs.json", "fonts/NotoSansJP-Regular.otf", "LICENSE")
               if not (base_assets / name).is_file()]
    missing += [f"textures/{name}.png|jpg" for name in TEXTURES
                if not any((base_assets / "textures" / f"{name}.{ext}").is_file() for ext in ("png", "jpg"))]
    if missing:
        raise ValueError("Missing EDOPro base assets: " + ", ".join(missing))

    script_archive = None
    if scripts.is_file():
        script_hashes = {item["sha256"] for name, item in downloads.items() if "CardScripts" in name and name.endswith(".zip")}
        if digest(scripts) not in script_hashes:
            raise ValueError("CardScripts archive hash differs from pinned audit")
        script_archive = zipfile.ZipFile(scripts)
        try:
            script_entries = archive_entries(script_archive)
            roots = [name[:-len("constant.lua")] for name in script_entries if name.endswith("/constant.lua")]
            if "constant.lua" in script_entries:
                roots.append("")
            roots = [root for root in roots if root + "utility.lua" in script_entries]
            if len(roots) != 1:
                raise ValueError("Ambiguous CardScripts archive root")
            script_root = roots[0]
            source_scripts = [(name[len(script_root):], name) for name in script_entries if name.startswith(script_root)]
        except Exception:
            script_archive.close()
            raise
    else:
        commit = subprocess.check_output(["git", "-C", str(scripts), "rev-parse", "HEAD"], text=True).strip()
        if commit != audit["sources"]["CardScripts"]["commit"]:
            raise ValueError("CardScripts directory is not the audited commit")
        if subprocess.check_output(["git", "-C", str(scripts), "status", "--porcelain"], text=True).strip():
            raise ValueError("CardScripts checkout has local changes")
        tracked = subprocess.check_output(["git", "-C", str(scripts), "ls-files", "-z"]).decode().split("\0")
        source_scripts = [(name, scripts / safe_relative(name)) for name in tracked if name]

    output.parent.mkdir(parents=True, exist_ok=True)
    stage = output.with_name(output.name + ".staging-" + uuid.uuid4().hex)
    stage.mkdir()
    try:
        logging.info("Copying pinned base UI assets")
        for folder in BASE_DIRS:
            if (base_assets / folder).is_dir():
                copy_tree(base_assets / folder, stage / folder)
        copy_file(base_assets / "LICENSE", stage / "licenses/Distribution-LICENSE")
        if (base_assets / "README.md").is_file():
            copy_file(base_assets / "README.md", stage / "licenses/Distribution-README.md")
        copy_file(cdb, stage / "cards.cdb")
        cdb_notice = cdb.with_name("BabelCDB-" + audit["sources"]["BabelCDB"]["commit"] + "-README.md")
        if cdb_notice.is_file():
            copy_file(cdb_notice, stage / "licenses/BabelCDB-README.md")
        logging.info("Copying %d script and licence files", len(source_scripts))
        for relative, source in source_scripts:
            target = stage / "script" / safe_relative(relative)
            target.parent.mkdir(parents=True, exist_ok=True)
            if script_archive:
                target.write_bytes(script_archive.read(source))
            else:
                copy_file(source, target)
        if not (stage / "script/constant.lua").is_file() or not (stage / "script/utility.lua").is_file():
            raise ValueError("Missing full script utility library")
        # Pin ordinary card lookup to official scripts; keep every variant in its original subdirectory.
        script_resolution = []
        logging.info("Pinning official script lookup and recording alternate versions")
        variants_by_name: dict[str, list[Path]] = {}
        for variant in (stage / "script").rglob("c*.lua"):
            variants_by_name.setdefault(variant.name, []).append(variant)
        for official in sorted((stage / "script/official").glob("c*.lua")):
            if not re.fullmatch(r"c\d+\.lua", official.name):
                continue
            destination = stage / "script" / official.name
            if destination.exists() and digest(destination) != digest(official):
                raise ValueError(f"Conflicting root script: {official.name}")
            copy_file(official, destination)
            variants = [path.relative_to(stage / "script").as_posix()
                        for path in variants_by_name[official.name]
                        if path != destination and digest(path) != digest(official)]
            if variants:
                script_resolution.append({"code": int(official.stem[1:]), "selected": "official/" + official.name,
                                          "otherVariants": sorted(variants), "reason": "Official version wins for the pinned current database"})
        script_overrides = audit["bridge"].get("scriptOverrides", [])
        if isinstance(script_overrides, dict):
            commit = audit["sources"]["CardScripts"]["commit"]
            script_overrides = [{"coreCode": int(code), "path": path,
                                 "evidence": f"https://github.com/ProjectIgnis/CardScripts/blob/{commit}/{path}",
                                 "reason": "Explicit reviewed pre-errata script selection; see mapping audit"}
                                for code, path in script_overrides.items()]
        for override in script_overrides:
            relative = safe_relative(override["path"])
            original = stage / "script" / relative
            code = override["coreCode"]
            if type(code) is not int or code not in database or not override.get("evidence"):
                raise ValueError("Invalid explicit script override")
            destination = stage / "script" / f"c{code}.lua"
            if destination.exists() and digest(destination) != digest(original):
                raise ValueError("Script override would replace an official version")
            copy_file(original, destination)
            script_resolution.append({**override, "selected": relative.as_posix()})
        # Freeze the audited local scripts/database; do not fetch mutable remote repos at launch.
        config_path = stage / "config/configs.json"
        config = json.loads(config_path.read_text(encoding="utf-8-sig"))
        config["repos"] = []; config["urls"] = []; config["servers"] = []
        config_path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        user_path = stage / "config/user_configs.json"
        user_config = json.loads(user_path.read_text(encoding="utf-8-sig")) if user_path.exists() else {}
        user_config["repos"] = []; user_config["urls"] = []; user_config["servers"] = []
        user_path.write_text(json.dumps(user_config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        system_path = stage / "config/system.conf"
        system = system_path.read_text(encoding="utf-8-sig") if system_path.exists() else ""
        system = re.sub(r"(?m)^noClientUpdates\s*=.*\n?", "", system)
        system_path.write_text(system.rstrip() + "\nnoClientUpdates = 1\n", encoding="utf-8")

        logging.info("Converting OBB decks, art and audio without modifying the archive")
        deck_report, image_report, audio_report, codes_written = [], [], [], set()
        with zipfile.ZipFile(obb) as source:
            entries = archive_entries(source)
            prop = source.read("assets/CARD_Prop.bin")
            passwords = source.read("assets/CARD_Pass.bin")
            if len(prop) % 8 or len(passwords) != len(prop) // 2:
                raise ValueError("Invalid Prop/Pass alignment")
            for index, (first, _) in enumerate(struct.iter_unpack("<II", prop)):
                kid, password = first & 0x3FFF, struct.unpack_from("<I", passwords, index * 4)[0]
                if password and kid in mapping and mapping[kid] != password:
                    raise ValueError("Mapping does not preserve source password")
            def entry_order(name: str) -> tuple[int, str]:
                stem = PurePosixPath(name).stem
                canonical = stem.isascii() and stem.isdigit() and PurePosixPath(name).name == f"{int(stem):04d}.jpg"
                return (0 if canonical else 1, name)
            for name in sorted(entries, key=entry_order):
                if name.lower().endswith(".ydc"):
                    original = decode_deck(source.read(name))
                    converted = {zone: [mapping.get(kid) for kid in original[zone]] for zone in ("main", "extra", "side")}
                    unresolved = [{"zone": zone, "index": index, "konamiID": kid}
                                  for zone in converted for index, kid in enumerate(original[zone]) if converted[zone][index] is None]
                    problems = [] if unresolved else deck_problems(converted, database)
                    record = {"source": name, "sourceKonamiIDs": original, "coreCodes": converted,
                              "unresolved": unresolved, "deckProblems": problems,
                              "eligibleForLocalDuel": not unresolved and not problems}
                    relative = safe_relative(name).with_suffix(".ydk")
                    if not unresolved:
                        record["convertedFile"] = (Path("converted-decks") / relative).as_posix()
                        write_ydk(stage / record["convertedFile"], converted)
                        if not problems:
                            record["deckFile"] = (Path("deck") / client_deck_filename(name)).as_posix()
                            if (stage / record["deckFile"]).exists():
                                raise ValueError("Colliding generated deck filenames")
                            write_ydk(stage / record["deckFile"], converted)
                    else:
                        record["preservedSource"] = (Path("unresolved-decks") / safe_relative(name)).as_posix()
                        target = stage / record["preservedSource"]
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_bytes(source.read(name))
                    deck_report.append(record)
                elif name.lower().endswith(".jpg"):
                    stem = PurePosixPath(name).stem
                    kid = int(stem) if stem.isascii() and stem.isdigit() else None
                    code = mapping.get(kid)
                    if code and code not in codes_written:
                        relative = Path("pics") / f"{code}.jpg"
                        codes_written.add(code)
                    else:
                        relative = Path("obb-art") / safe_relative(name)
                    data = source.read(name)
                    target = stage / relative
                    target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(data)
                    image_report.append({"source": name, "konamiID": kid, "coreCode": code,
                                         "output": relative.as_posix(), "sha256": hashlib.sha256(data).hexdigest()})
                elif name.lower().endswith(".mp3"):
                    filename = PurePosixPath(name).name
                    if filename == "bgm_menu.mp3":
                        relative = Path("sound/BGM/menu/obb-menu.mp3")
                    elif filename == "bgm_deck.mp3":
                        relative = Path("sound/BGM/deck/obb-deck.mp3")
                    elif filename.startswith("duel_"):
                        relative = Path("sound/BGM/duel") / filename
                    elif filename in ("bgm_result_lose1.mp3", "bgm_result_lose2.mp3"):
                        relative = Path("sound/BGM/lose") / filename
                    else:
                        relative = Path("obb-audio") / safe_relative(name)
                    data = source.read(name)
                    target = stage / relative
                    if target.exists():
                        raise ValueError(f"OBB audio would replace a base asset: {relative}")
                    target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(data)
                    audio_report.append({"source": name, "output": relative.as_posix(),
                                         "sha256": hashlib.sha256(data).hexdigest(),
                                         "usedAsMusic": relative.parts[0] == "sound"})
        (stage / "reports").mkdir(exist_ok=True)
        locale_report = None
        if include_vi:
            logging.info("Preparing optional OBB Vietnamese text locale; default language stays unchanged")
            from create_obb_locale import create_locale
            locale_report = create_locale(obb, cdb, mapping, audit, stage / "config/languages/vi-obb")
        if source_lock:
            copy_file(source_lock, stage / "reports/upstream.lock.json")
        if offline_ai is not None:
            if not offline_ai.is_file() or offline_ai.stat().st_size == 0:
                raise ValueError("Missing offline AI decision module")
            copy_file(offline_ai, stage / "offline-ai/offline_ai.js")
        for filename, data in (("decks.json", deck_report), ("images.json", image_report),
                               ("audio.json", audio_report),
                               ("reviewed-mappings.json", overrides), ("mapping-audit.json", audit),
                               ("script-resolution.json", script_resolution)):
            (stage / "reports" / filename).write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        logging.info("Hashing all prepared assets for the deterministic package manifest")
        manifest = {path.relative_to(stage).as_posix(): {"sha256": digest(path), "bytes": path.stat().st_size}
                    for path in sorted(stage.rglob("*")) if path.is_file()}
        summary = {"schemaVersion": 1, "sourceOBBSHA256": digest(obb), "sourceCDBSHA256": digest(cdb),
                   "sourcePins": {key: audit["sources"][key] for key in ("BabelCDB", "CardScripts")},
                   "sourceLockSHA256": digest(source_lock) if source_lock else None,
                   "deckCount": len(deck_report), "mappedDecks": sum(not row["unresolved"] for row in deck_report),
                   "localDuelDecks": sum(row["eligibleForLocalDuel"] for row in deck_report),
                   "unresolvedDecks": sum(bool(row["unresolved"]) for row in deck_report),
                   "sourceJPGs": len(image_report), "passcodePictures": len(codes_written),
                   "sourceMP3s": len(audio_report), "mappedMusicFiles": sum(row["usedAsMusic"] for row in audio_report),
                   "pictureFormat": "art-only from OBB", "nativeCardFaceRenderingRequired": True,
                   "missingMappedPictures": sorted(set(mapping.values()) - codes_written),
                   "optionalLocale": locale_report,
                   "offlineAIIncluded": offline_ai is not None,
                   "scriptFiles": len(source_scripts), "buildExecuted": False,
                   "limitations": ["No runtime verification", "No banlist legality check", "Native offline AI bridge not runtime verified",
                                   "Current database/errata may differ from original OBB effects; consult mapping audit"],
                   "files": manifest}
        (stage / "package-manifest.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
        stage.rename(output)
        logging.info("Prepared asset payload: %s", output)
        return summary
    except Exception:
        (stage / "INCOMPLETE.txt").write_text("Asset preparation failed; do not bundle this staging directory.\n", encoding="utf-8")
        raise
    finally:
        if script_archive:
            script_archive.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("obb", "cdb", "scripts", "base-assets", "audit"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--out", "--output", type=Path, required=True)
    parser.add_argument("--reviewed-mappings", type=Path)
    parser.add_argument("--source-lock", type=Path)
    parser.add_argument("--include-vi", action="store_true", help="Include the audited OBB Vietnamese text locale without making it the default")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    result = prepare(args.obb, args.cdb, args.scripts, args.base_assets, args.audit, args.out,
                     args.reviewed_mappings, args.source_lock, args.include_vi,
                     Path(__file__).resolve().parents[1] / "NativeClient/overlays/offline-ai/offline_ai.js")
    print(json.dumps({key: value for key, value in result.items() if key != "files"}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
