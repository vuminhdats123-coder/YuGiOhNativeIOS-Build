#!/usr/bin/env python3
"""Extract and inventory the Android OBB for the native rewrite.
Keeps binary formats opaque; only decodes UTF-16LE CARD name/description tables.
"""
from pathlib import Path
import argparse, json, zipfile

def split_utf16(blob):
    return blob.decode("utf-16le", "ignore").split("\x00")

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("obb", type=Path); ap.add_argument("out", type=Path)
    a=ap.parse_args(); a.out.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(a.obb) as z:
        files=[]
        for i in z.infolist(): files.append({"path":i.filename,"bytes":i.file_size,"crc":f"{i.CRC:08x}"})
        (a.out/"obb-manifest.json").write_text(json.dumps(files,ensure_ascii=False,indent=2),encoding="utf-8")
        names=split_utf16(z.read("assets/CARD_Name_E.bin")); desc=split_utf16(z.read("assets/CARD_Desc_E.bin"))
        cards=[]
        for idx,name in enumerate(names):
            name=" ".join(name.split())
            if name: cards.append({"sourceIndex":idx,"name":name,"description":" ".join(desc[idx].split()) if idx<len(desc) else ""})
        (a.out/"cards-en.json").write_text(json.dumps(cards,ensure_ascii=False,separators=(",",":")),encoding="utf-8")
        for n in ("CARD_IntID.bin","CARD_Prop.bin","CARD_Genre.bin","CARD_Pack.bin","CARD_Pass.bin","CARD_Sort_E.bin"):
            if n in z.namelist(): (a.out/(n+".bin")).write_bytes(z.read("assets/"+n))
    print(f"wrote {len(files)} files and {len(cards)} cards")
if __name__=="__main__": main()
