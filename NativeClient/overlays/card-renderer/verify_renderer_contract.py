"""Validate renderer layout, source-threading contracts and real metadata without compiling native code."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import sqlite3
import struct
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def jpeg_size(data):
    if data[:2] != b"\xff\xd8":
        raise ValueError("Not a JPEG")
    offset = 2
    while offset + 4 <= len(data):
        if data[offset] != 0xFF:
            raise ValueError("Invalid JPEG segment")
        while offset < len(data) and data[offset] == 0xFF:
            offset += 1
        if offset >= len(data):
            break
        marker = data[offset]
        offset += 1
        if marker in (0xD9, 0xDA):
            break
        if marker == 0x01 or 0xD0 <= marker <= 0xD7:
            continue
        length = struct.unpack_from(">H", data, offset)[0]
        if length < 2 or offset + length > len(data):
            raise ValueError("Truncated JPEG segment")
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            if length < 8:
                raise ValueError("Truncated JPEG frame")
            height, width = struct.unpack_from(">HH", data, offset + 3)
            return width, height
        offset += length
    raise ValueError("JPEG has no supported frame header")


def validate_layout():
    header = (HERE / "card_face_layout.h").read_text(encoding="utf-8")
    width = float(re.search(r"constexpr double Width = ([\d.]+)", header)[1])
    height = float(re.search(r"constexpr double Height = ([\d.]+)", header)[1])
    rects = {name: tuple(map(float, values.split(","))) for name, values in
             re.findall(r"constexpr Rect (\w+) = \{([^}]+)\}", header)}
    assert width / height == 177 / 254
    for name, (x, y, w, h) in rects.items():
        assert x >= 0 and y >= 0 and w > 0 and h > 0 and x + w <= width and y + h <= height, name
    def overlaps(a, b):
        x, y, w, h = rects[a]; xx, yy, ww, hh = rects[b]
        return x < xx + ww and xx < x + w and y < yy + hh and yy < y + h
    shared = ["Title", "Attribute", "Level", "TypeLine", "Description", "Statistics", "Footer"]
    for image in ("Art", "LinkArt", "PendulumArt"):
        zones = shared + [image]
        if image == "PendulumArt": zones += ["PendulumText", "LeftScale", "RightScale"]
        for index, a in enumerate(zones):
            for b in zones[index + 1:]: assert not overlaps(a, b), (image, a, b)
    x, y, w, h = rects["LinkArt"]
    assert y - 17 - 14 >= rects["Title"][1] + rects["Title"][3]
    assert y + h + 17 + 14 < rects["TypeLine"][1]
    assert x - 17 - 14 >= 0 and x + w + 17 + 14 <= width
    return {"width": width, "height": height, "regions": len(rects), "overlapChecks": "passed"}


def validate_source_contract():
    header = (ROOT / "NativeClient/edopro/gframe/image_manager.h").read_text(encoding="utf-8")
    source = (ROOT / "NativeClient/edopro/gframe/image_manager.cpp").read_text(encoding="utf-8")
    renderer = (HERE / "card_face.mm").read_text(encoding="utf-8")
    assert "face(std::move(face_))" in header, "Queue must retain the caller's immutable metadata snapshot"
    assert "std::shared_ptr<const CardFaceData> face;" in header
    worker = source.split("ImageManager::load_return ImageManager::LoadCardTexture", 1)[1].split("ImageManager::GetTextureCard", 1)[0]
    assert "gDataManager" not in worker, "Image workers must not read a mutable card/locale database"
    assert "addTexture(" not in worker and "getTexture(" not in worker, "Image worker must not upload GPU textures"
    assert "gDataManager" not in renderer and "IVideoDriver" not in renderer
    assert "loaded.face.get()" in source and "loaded.timestamp != loaded.reference_timestamp.load()" in source
    assert "RenderIOSCardFace(*face" in worker and "LoadImg(nullptr)" in worker
    assert "createMemoryReadFile" in worker and "Full text in card details" in renderer
    assert "[ Flavor Text ]" in renderer and "[ Monster Effect ]" in renderer
    return "Queue ownership / CPU-only worker / locale snapshot / fallback wiring checked statically"


def validate_data(cdb, obb):
    categories = Counter(); pendulum = 0; links = 0; longest_name = 0; longest_text = 0
    source = (HERE / "card_face.mm").read_text(encoding="utf-8")
    constants = {}
    for line in source.splitlines():
        if line.startswith("constexpr uint32_t "):
            constants.update({name: int(value, 0) for name, value in re.findall(r"(\w+)\s*=\s*(0x[\da-fA-F]+|\d+)", line)})
    db = sqlite3.connect(cdb.resolve().as_uri() + "?mode=ro", uri=True)
    try:
        rows = db.execute("SELECT datas.id,type,level,atk,def,race,attribute,texts.name,texts.desc FROM datas JOIN texts USING(id)").fetchall()
        for code, kind, level, atk, defense, race, attribute, name, description in rows:
            assert isinstance(name, str) and name and isinstance(description, str), code
            name.encode("utf-8", errors="strict"); description.encode("utf-8", errors="strict")
            longest_name = max(longest_name, len(name)); longest_text = max(longest_text, len(description))
            family = next((family for family in ("Spell", "Trap", "Link", "Xyz", "Synchro", "Fusion", "Ritual", "Normal")
                           if kind & constants[family]), "EffectOrOther")
            categories[family] += 1
            if kind & constants["Pendulum"]:
                pendulum += 1
                assert 0 <= (level >> 24) & 255 <= 255 and 0 <= (level >> 16) & 255 <= 255
            if kind & constants["Link"]:
                links += 1
                assert defense >= 0 and defense & ~0x1EF == 0, (code, defense)
    finally:
        db.close()
    dimensions = Counter()
    with zipfile.ZipFile(obb) as archive:
        for name in archive.namelist():
            if name.lower().endswith(".jpg"):
                w, h = jpeg_size(archive.read(name))
                assert w > 0 and h > 0
                dimensions[f"{w}x{h}"] += 1
    return {"metadataCards": len(rows), "frameCategories": dict(categories), "pendulumCards": pendulum,
            "linkCards": links, "longestNameCharacters": longest_name, "longestDescriptionCharacters": longest_text,
            "sourceJPGDimensions": dict(dimensions)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cdb", type=Path, default=ROOT / "outputs/ocg-reference/BabelCDB-6e21009855ed5f3b5966a24545bd0db393d44697-cards.cdb")
    parser.add_argument("--obb", type=Path, default=ROOT / "com.konami.ygodgtest/main.116.com.konami.ygodgtest.obb")
    parser.add_argument("--report", type=Path, default=ROOT / "outputs/card-renderer-validation.json")
    args = parser.parse_args()
    report = {"layout": validate_layout(), "sourceContract": validate_source_contract(),
              "data": validate_data(args.cdb, args.obb), "nativeBitmapTestsExecuted": False,
              "nativeCompileExecuted": False, "visualDeviceVerification": False}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
