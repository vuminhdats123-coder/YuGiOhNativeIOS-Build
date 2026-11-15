import zipfile,glob,struct,json
from pathlib import Path
obb=glob.glob('com.konami.ygodgtest/*.obb')[0]
with zipfile.ZipFile(obb) as z:
 idx=struct.unpack('<%dI'%(len(z.read('assets/CARD_Indx_E.bin'))//4),z.read('assets/CARD_Indx_E.bin'))
 n=z.read('assets/CARD_Name_E.bin'); d=z.read('assets/CARD_Desc_E.bin')
 def text(blob,offset): return blob[offset:].decode('utf-16le','ignore').split('\0',1)[0].strip()
 rows=[]
 for i in range(len(idx)//2-1):
  name=text(n,idx[2*i]);
  if name: rows.append({'id':i,'sourceIndex':i,'name':name,'description':text(d,idx[2*i+1])})
for out in ['YuGiOhNativeIOS/GeneratedData/cards-en.json','YuGiOhNativeIOS/Resources/cards_en.json']:
 Path(out).write_text(json.dumps(rows,ensure_ascii=False,separators=(',',':')),encoding='utf8')
print('rows',len(rows),rows[:3])
