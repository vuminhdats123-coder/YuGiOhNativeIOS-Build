#!/usr/bin/env python3
"""Extract OBB tables and produce a machine-readable inventory."""
from pathlib import Path
import argparse, json, zipfile

def split_utf16(blob):
    return blob.decode("utf-16le", "ignore").split("\x00")

def clean(value): return " ".join(value.split())

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("obb",type=Path); ap.add_argument("out",type=Path); ap.add_argument("--images", action="store_true", help="extract JPG card images"); a=ap.parse_args()
    a.out.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(a.obb) as z:
        infos=z.infolist(); names=z.namelist();
        (a.out/"obb-manifest.json").write_text(json.dumps([{"path":i.filename,"bytes":i.file_size,"crc":f"{i.CRC:08x}"} for i in infos],ensure_ascii=False,indent=2),encoding="utf-8")
        tables=[]
        for n in names:
            if not n.startswith("assets/CARD_"): continue
            info=z.getinfo(n); out_name=Path(n).name
            raw=z.read(n)
            (a.out/out_name).write_bytes(raw)
            row={"file":out_name,"bytes":info.file_size,"crc":f"{info.CRC:08x}","encoding":"binary"}
            if out_name.startswith(("CARD_Name_","CARD_Desc_","CARD_Kana")) and len(raw)%2==0:
                values=split_utf16(raw); row["encoding"]="utf-16le-null"; row["records"]=len(values); row["nonEmpty"]=sum(bool(clean(v)) for v in values)
                (a.out/(out_name+".json")).write_text(json.dumps([clean(v) for v in values],ensure_ascii=False,separators=(",",":")),encoding="utf-8")
            tables.append(row)
        names_e=split_utf16(z.read("assets/CARD_Name_E.bin")); desc_e=split_utf16(z.read("assets/CARD_Desc_E.bin"))
        cards=[{"sourceIndex":i,"name":clean(n),"description":clean(desc_e[i]) if i<len(desc_e) else ""} for i,n in enumerate(names_e) if clean(n)]
        (a.out/"cards-en.json").write_text(json.dumps(cards,ensure_ascii=False,separators=(",",":")),encoding="utf-8")
        if a.images:
            image_dir=a.out/"CardImages"; image_dir.mkdir(exist_ok=True)
            for n in names:
                if n.lower().endswith(".jpg"):
                    (image_dir/Path(n).name).write_bytes(z.read(n))
        (a.out/"card-tables.json").write_text(json.dumps(tables,ensure_ascii=False,indent=2),encoding="utf-8")
    print(f"wrote {len(infos)} files, {len(tables)} CARD tables and {len(cards)} cards")
if __name__=="__main__": main()
