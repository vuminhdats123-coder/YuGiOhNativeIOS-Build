#!/usr/bin/env python3
import argparse,json,struct,zipfile
from pathlib import Path

def main():
 ap=argparse.ArgumentParser(); ap.add_argument('obb',type=Path); ap.add_argument('--out',type=Path,default=Path('YuGiOhNativeIOS/GeneratedData/card-table-summary.json')); a=ap.parse_args()
 rows=[]
 with zipfile.ZipFile(a.obb) as z:
  for n in sorted(x for x in z.namelist() if x.startswith('assets/CARD_') and x.endswith('.bin')):
   d=z.read(n); base=Path(n).name
   row={'file':base,'bytes':len(d),'nonZeroBytes':sum(b!=0 for b in d)}
   if base in ('CARD_Prop.bin','CARD_Genre.bin'): row['recordBytes']=8; row['records']=len(d)//8
   elif base.startswith('CARD_Indx_'): row['recordBytes']=8; row['records']=len(d)//8-1
   elif base.startswith(('CARD_Name_','CARD_Desc_')): row['encoding']='utf-16le-offset-table'
   elif base in ('CARD_Pass.bin','CARD_Prop.bin'): row['recordBytes']=4; row['records']=len(d)//4
   elif base.startswith(('CARD_Sort','CARD_Kana1_')): row['recordBytes']=2; row['records']=len(d)//2
   else: row['format']='raw-opaque'
   rows.append(row)
 rows=a.out.write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf8'); print('tables',len(rows))
if __name__=='__main__': main()

