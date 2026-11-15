#!/usr/bin/env python3
"""Extract OBB tables and produce a machine-readable inventory."""
from pathlib import Path
import argparse, json, zipfile, struct
from verify_obb_data import text_at as read_text

def text_at(blob, offset):
    value = read_text(blob, offset)
    if value is None:
        raise ValueError(f"Invalid UTF-16 string offset: {offset}")
    return value.strip()

def clean(value): return " ".join(value.split())

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("obb",type=Path); ap.add_argument("out",type=Path); ap.add_argument("--images", action="store_true", help="extract JPG card images"); a=ap.parse_args()
    a.out.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(a.obb) as z:
        infos=z.infolist(); names=z.namelist();
        (a.out/"obb-manifest.json").write_text(json.dumps([{"path":i.filename,"bytes":i.file_size,"crc":f"{i.CRC:08x}"} for i in infos],ensure_ascii=False,indent=2),encoding="utf-8")
        tables=[]
        for n in names:
            if not n.startswith("assets/CARD_") or not n.endswith(".bin"): continue
            info=z.getinfo(n); out_name=Path(n).name
            raw=z.read(n)
            (a.out/out_name).write_bytes(raw)
            row={"file":out_name,"bytes":info.file_size,"crc":f"{info.CRC:08x}","encoding":"binary"}
            if out_name.startswith(("CARD_Name_", "CARD_Desc_")):
                row["encoding"] = "utf-16le-offset-table"
            tables.append(row)
        offsets=struct.unpack("<%dI" % (len(z.read("assets/CARD_Indx_E.bin"))//4), z.read("assets/CARD_Indx_E.bin"))
        names_e=z.read("assets/CARD_Name_E.bin"); desc_e=z.read("assets/CARD_Desc_E.bin")
        cards=[]
        for i in range(len(offsets)//2 - 1):
            name=text_at(names_e, offsets[2*i])
            if name: cards.append({"id":i,"sourceIndex":i,"name":name,"description":text_at(desc_e, offsets[2*i+1])})
        (a.out/"cards-en.json").write_text(json.dumps(cards,ensure_ascii=False,separators=(",",":")),encoding="utf-8")
        if a.images:
            image_dir=a.out/"CardImages"; image_dir.mkdir(exist_ok=True)
            for n in names:
                if n.lower().endswith(".jpg"):
                    (image_dir/Path(n).name).write_bytes(z.read(n))
        (a.out/"card-tables.json").write_text(json.dumps(tables,ensure_ascii=False,indent=2),encoding="utf-8")
    print(f"wrote {len(infos)} files, {len(tables)} CARD tables and {len(cards)} cards")
if __name__=="__main__": main()
