#!/usr/bin/env python3
import argparse,json,struct,zipfile
from pathlib import Path

def u16(data): return list(struct.unpack('<%dH'%(len(data)//2),data))
def main():
 ap=argparse.ArgumentParser(); ap.add_argument('obb',type=Path); ap.add_argument('--out',type=Path,default=Path('YuGiOhNativeIOS/GeneratedData/card-relations.json')); args=ap.parse_args()
 with zipfile.ZipFile(args.obb) as z:
  named=u16(z.read('assets/CARD_Named.bin')); count=named[0] if named else 0; named_rows=[]
  for code in range(count):
   off=2+2*count+named[2+2*code]; length=named[3+2*code]; named_rows.append({'code':code,'cardIds':named[off:off+length]})
  same=z.read('assets/CARD_Same.bin'); same_rows=[{'card':a,'target':b,'mode':m,'modeName':'while-effect' if m==0x100 else 'always' if m==0 else f'0x{m:x}'} for a,b,m in struct.iter_unpack('<HHH',same)]
  link=z.read('assets/CARD_Link.bin'); links=[]
  for card,target in struct.iter_unpack('<HH',link):
   kind='card' if target>=3900 else 'counter' if target>=1000 else 'archetype' if target>=1 else 'unknown'; links.append({'card':card,'target':target,'targetKind':kind})
  sort={};
  for lang in 'EFGIJRS':
   rank=u16(z.read(f'assets/CARD_Sort_{lang}.bin')); order=u16(z.read(f'assets/CARD_Sort2_{lang}.bin')); consistent=len(rank)==len(order) and all(i<len(rank) and rank[i]==p for p,i in enumerate(order))
   sort[lang]={'records':len(rank),'consistent':consistent,'rank':rank,'order':order}
  kana={}
  for lang in 'EFGIJRS':
   a=u16(z.read(f'assets/CARD_Kana1_{lang}.bin')); b=u16(z.read(f'assets/CARD_Kana2_{lang}.bin')); c=u16(z.read(f'assets/CARD_Kana3_{lang}.bin')); kana[lang]=[''.join(chr(x) for x in (a[i],b[i],c[i]) if x).rstrip('\0') for i in range(min(len(a),len(b),len(c)))]
  pack=z.read('assets/CARD_Pack.bin'); pack_vals=u16(pack)
 out={'named':{'count':count,'archetypes':named_rows},'same':{'records':same_rows},'links':{'records':links},'sort':sort,'kana':kana,'pack':{'bytes':len(pack),'u16Records':len(pack_vals),'values':pack_vals}}
 args.out.parent.mkdir(parents=True,exist_ok=True); args.out.write_text(json.dumps(out,ensure_ascii=False,separators=(',',':')),encoding='utf8'); print('named',count,'same',len(same_rows),'links',len(links))
if __name__=='__main__': main()
