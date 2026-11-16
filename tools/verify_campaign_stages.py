from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

SAFE_ICON = re.compile(r"^[A-Za-z0-9_.-]+\.png$")


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def validate(stages_path: Path, portrait_catalog_path: Path, portrait_root: Path) -> list[str]:
    errors: list[str] = []
    stages_doc = read_json(stages_path)
    if stages_doc.get("schemaVersion") != 1:
        errors.append("schemaVersion must be 1")
    stages = stages_doc.get("stages")
    if not isinstance(stages, list) or not stages:
        return ["stages must be a non-empty array"]
    ids = [item.get("id") for item in stages]
    if ids != list(range(1, len(stages) + 1)):
        errors.append("stage ids must be contiguous starting at 1")
    catalog = read_json(portrait_catalog_path)
    decks = catalog.get("decks")
    if not isinstance(decks, dict):
        errors.append("duel portrait catalog must contain a decks object")
        decks = {}
    seen_keys: set[str] = set()
    seen_titles: set[str] = set()
    previous_unlock = -1
    for index, stage in enumerate(stages, 1):
        if not isinstance(stage, dict):
            errors.append(f"stage {index} must be an object")
            continue
        stage_id = stage.get("id", index)
        title = stage.get("title")
        key = stage.get("deckKey")
        icon = stage.get("icon")
        unlock = stage.get("unlockAfterWins")
        if not isinstance(title, str) or not title.strip() or title in seen_titles:
            errors.append(f"stage {stage_id}: title must be non-empty and unique")
        else:
            seen_titles.add(title)
        if not isinstance(key, str) or key in seen_keys:
            errors.append(f"stage {stage_id}: deckKey must be unique")
        else:
            seen_keys.add(key)
        if not isinstance(unlock, int) or unlock < 0 or unlock < previous_unlock:
            errors.append(f"stage {stage_id}: unlockAfterWins must be non-negative and non-decreasing")
        else:
            previous_unlock = unlock
        entry = decks.get(key) if isinstance(key, str) else None
        if not isinstance(entry, dict):
            errors.append(f"stage {stage_id}: deckKey missing from portrait catalog: {key}")
            continue
        catalog_icon = entry.get("icon")
        if icon != catalog_icon:
            errors.append(f"stage {stage_id}: icon does not match portrait catalog")
        if not isinstance(icon, str) or not SAFE_ICON.fullmatch(icon):
            errors.append(f"stage {stage_id}: unsafe icon name")
        elif not (portrait_root / icon).is_file():
            errors.append(f"stage {stage_id}: portrait file missing: {icon}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate native Campaign stage/portrait mapping")
    parser.add_argument("--stages", type=Path, required=True)
    parser.add_argument("--portrait-catalog", type=Path, required=True)
    parser.add_argument("--portrait-root", type=Path, required=True)
    args = parser.parse_args()
    errors = validate(args.stages, args.portrait_catalog, args.portrait_root)
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print(f"Campaign portrait mapping valid: {len(read_json(args.stages)['stages'])} stages")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
