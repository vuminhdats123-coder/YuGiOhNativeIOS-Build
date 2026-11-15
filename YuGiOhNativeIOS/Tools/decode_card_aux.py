import argparse,json,struct,zipfile
from pathlib import Path

def u16(d): return list(struct.unpack('<%dH'%(len(d)//2),d)) if len(d)%2==0 else []
def u32(d): return list(struct.unpack('<%dI'%(len(d)//4),d)) if len(d)%4==0 else []
def main():
 ap=argparse.ArgumentParser(); ap.add_argument('obb',type=Path); ap.add_argument('--out',type=Path,default=Path('YuGiOhNativeIOS/GeneratedData/card-aux-tables.json')); args=ap.parse_args(); payload={}
 with zipfile.ZipFile(args.obb) as z:
  for base,kind in [('CARD_Pack.bin','u16'),('CARD_Named.bin','u16'),('CARD_Same.bin','u16'),('CARD_Link.bin','u32')]:
   data=z.read('assets/'+base); vals=u16(data) if kind=='u16' else u32(data); payload[base]={'encoding':kind,'bytes':len(data),'records':len(vals),'values':vals}
  for base in ['CARD_Sort_E.bin','CARD_Sort2_E.bin','CARD_Kana1_E.bin','CARD_Kana2_E.bin','CARD_Kana3_E.bin']:
   data=z.read('assets/'+base); vals=u16(data); payload[base]={'encoding':'u16','bytes':len(data),'records':len(vals),'values':vals}
 args.out.parent.mkdir(parents=True,exist_ok=True); args.out.write_text(json.dumps(payload,ensure_ascii=False,separators=(',',':')),encoding='utf8'); print('tables',len(payload))
if __name__=='__main__': main()
