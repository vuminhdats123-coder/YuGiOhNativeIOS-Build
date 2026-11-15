"""Xcode resource phase: verify and copy the complete tree to App.app/game.

Never runs a compiler, generator, SDK tool, network request, or signing tool.
The destination must be an existing .app directory. Only this tool's game
directory is replaced; existing executable, Info.plist and other resources stay.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import uuid

REQUIRED = {
    "cards.cdb", "script/constant.lua", "script/utility.lua",
    "config/strings.conf", "fonts/NotoSansJP-Regular.otf",
    "offline-ai/offline_ai.js",
}
ICON_NAMES = (
    "AppIcon20x20@2x.png", "AppIcon20x20@3x.png",
    "AppIcon29x29@2x.png", "AppIcon29x29@3x.png",
    "AppIcon40x40@2x.png", "AppIcon40x40@3x.png",
    "AppIcon60x60@2x.png", "AppIcon60x60@3x.png",
    "AppIcon20x20~ipad.png", "AppIcon20x20@2x~ipad.png",
    "AppIcon29x29~ipad.png", "AppIcon29x29@2x~ipad.png",
    "AppIcon40x40~ipad.png", "AppIcon40x40@2x~ipad.png",
    "AppIcon76x76~ipad.png", "AppIcon76x76@2x~ipad.png",
    "AppIcon83.5x83.5@2x~ipad.png",
)


def safe_relative(value: str) -> Path:
    if not isinstance(value, str) or "\\" in value or ":" in value or "\x00" in value:
        raise ValueError("Invalid manifest path")
    pure = PurePosixPath(value)
    if pure.is_absolute() or not pure.parts or any(p in ("", ".", "..") for p in value.split("/")):
        raise ValueError(f"Unsafe manifest path: {value!r}")
    return Path(*pure.parts)


def regular(path: Path) -> None:
    if not stat.S_ISREG(path.lstat().st_mode):
        raise ValueError(f"Expected a regular file: {path}")


def inventory(root: Path) -> set[str]:
    if not stat.S_ISDIR(root.lstat().st_mode):
        raise ValueError(f"Expected a real directory: {root}")
    result = set()
    for directory, dirs, names in os.walk(root, followlinks=False):
        for name in dirs:
            if not stat.S_ISDIR((Path(directory) / name).lstat().st_mode):
                raise ValueError("Symbolic links are not allowed in game resources")
        for name in names:
            path = Path(directory) / name
            regular(path)
            result.add(path.relative_to(root).as_posix())
    return result


def read_manifest(source: Path) -> tuple[bytes, dict]:
    manifest_path = source / "package-manifest.json"
    regular(manifest_path)
    raw = manifest_path.read_bytes()
    data = json.loads(raw)
    files = data.get("files")
    if data.get("schemaVersion") != 1 or not isinstance(files, dict) or not REQUIRED <= set(files):
        raise ValueError("Incomplete or unsupported game manifest")
    seen = set()
    for name, entry in files.items():
        safe_relative(name)
        if name.casefold() in seen or name.casefold() == "package-manifest.json":
            raise ValueError("Duplicate or reserved manifest path")
        seen.add(name.casefold())
        if not isinstance(entry, dict) or not re.fullmatch(r"[0-9a-f]{64}", entry.get("sha256", "")):
            raise ValueError(f"Invalid SHA256 for {name}")
        if type(entry.get("bytes")) is not int or entry["bytes"] < 0:
            raise ValueError(f"Invalid byte count for {name}")
    if inventory(source) != set(files) | {"package-manifest.json"}:
        raise ValueError("Source resource inventory differs from its manifest")
    return raw, files


def remove_owned_stage(directory: Path, bundle: Path) -> None:
    # Resolve and constrain the exact recursive-delete target, including on Windows.
    if directory.is_symlink() or directory.resolve().parent != bundle.resolve() or not directory.name.startswith(".edopro-game-"):
        raise ValueError("Refusing to remove a directory outside the controlled app staging path")
    shutil.rmtree(directory)


def copy_resources(source: Path, icons: Path, bundle: Path) -> dict:
    if bundle.name.lower().endswith(".app") is False or not stat.S_ISDIR(bundle.lstat().st_mode):
        raise ValueError("Bundle destination must be an existing real .app directory")
    if bundle.resolve() == source.resolve() or source.resolve() in bundle.resolve().parents or bundle.resolve() in source.resolve().parents:
        raise ValueError("Source and application directory must be separate trees")
    raw, files = read_manifest(source)
    icon_data = {}
    for name in ICON_NAMES:
        regular(icons / name)
        payload = (icons / name).read_bytes()
        if not payload.startswith(b"\x89PNG\r\n\x1a\n"):
            raise ValueError(f"Invalid app icon PNG: {name}")
        icon_data[name] = payload
    destination = bundle / "game"
    if destination.exists() or destination.is_symlink():
        # Build products may be replaced; arbitrary non-package directories may not.
        read_manifest(destination)
    stage = bundle / (".edopro-game-stage-" + uuid.uuid4().hex)
    backup = bundle / (".edopro-game-old-" + uuid.uuid4().hex)
    stage.mkdir()
    try:
        for name, entry in files.items():
            relative = safe_relative(name)
            target = stage / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            digest = hashlib.sha256()
            size = 0
            with (source / relative).open("rb") as reader, target.open("xb") as writer:
                for block in iter(lambda: reader.read(1024 * 1024), b""):
                    digest.update(block)
                    size += len(block)
                    writer.write(block)
            if size != entry["bytes"] or digest.hexdigest() != entry["sha256"]:
                raise ValueError(f"Resource checksum mismatch: {name}")
        (stage / "package-manifest.json").write_bytes(raw)
        # Icons are explicitly allowlisted. Do not copy stale upstream signatures or Assets.car.
        for name, payload in icon_data.items():
            target = bundle / name
            if target.exists() or target.is_symlink():
                regular(target)
            target.write_bytes(payload)
        if destination.exists():
            destination.rename(backup)
        try:
            stage.rename(destination)
        except Exception:
            if backup.exists():
                backup.rename(destination)
            raise
        if backup.exists():
            remove_owned_stage(backup, bundle)
    finally:
        if stage.exists():
            remove_owned_stage(stage, bundle)
    return {"files": len(files), "bytes": sum(row["bytes"] for row in files.values()),
            "manifestSHA256": hashlib.sha256(raw).hexdigest(), "icons": len(icon_data)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--icons", required=True, type=Path)
    parser.add_argument("--bundle-root", required=True, type=Path)
    args = parser.parse_args()
    try:
        report = copy_resources(args.source, args.icons, args.bundle_root)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"EDOPro resource copy failed: {error}\n")
    print(json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
