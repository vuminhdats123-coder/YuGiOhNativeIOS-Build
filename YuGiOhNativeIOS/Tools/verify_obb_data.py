#!/usr/bin/env python3
import argparse, json, struct, zipfile, plistlib
from pathlib import Path

def text_at(blob, offset):
    if offset < 0 or offset >= len(blob): return None
    end = blob.find(b'\x00\x00', offset)
    if end < 0: end = len(blob)
    end -= end % 2
    try: return blob[offset:end].decode('utf-16le', 'strict')
    except UnicodeDecodeError: return None

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('obb',type=Path); ap.add_argument('--report',type=Path,default=Path('YuGiOhNativeIOS/GeneratedData/obb-validation.json')); a=ap.parse_args()
    report={'ok':True,'errors':[],'warnings':[],'counts':{}}
    with zipfile.ZipFile(a.obb) as z:
        names=set(z.namelist()); infos=z.infolist(); report['counts']['files']=len(infos)
        plist_errors=[]
        for info in infos:
            if info.filename.lower().endswith('.plist'):
                try: plistlib.loads(z.read(info.filename))
                except Exception as exc: plist_errors.append({'path':info.filename,'error':str(exc)})
        report['counts']['plistValid']=sum(1 for info in infos if info.filename.lower().endswith('.plist'))-len(plist_errors)
        if plist_errors: report['warnings'].append(f"{len(plist_errors)} plist files are not strict XML; the game may use a permissive parser")
        report['plistErrors']=plist_errors
        def require(n):
            if 'assets/'+n not in names: report['errors'].append('missing assets/'+n); return b''
            return z.read('assets/'+n)
        prop=require('CARD_Prop.bin'); genre=require('CARD_Genre.bin'); idx=require('CARD_Indx_E.bin'); intid=require('CARD_IntID.bin')
        for label,data,size in [('CARD_Prop',prop,8),('CARD_Genre',genre,8),('CARD_Indx_E',idx,8)]:
            if data and len(data)%size: report['errors'].append(f'{label} size {len(data)} not divisible by {size}')
        prop_count=len(prop)//8; genre_count=len(genre)//8; idx_count=len(idx)//8-1
        report['counts'].update(propRecords=prop_count,genreRecords=genre_count,textRecords=idx_count,intIdEntries=len(intid)//2,jpg=sum(n.lower().endswith('.jpg') for n in names),ydc=sum(n.lower().endswith('.ydc') for n in names),plist=sum(n.lower().endswith('.plist') for n in names),mp3=sum(n.lower().endswith('.mp3') for n in names))
        ydc_headers={}
        for n in names:
            if n.lower().endswith('.ydc'):
                h=z.read(n)[:2].hex(); ydc_headers[h]=ydc_headers.get(h,0)+1
        report['ydcHeaders']=ydc_headers
        if prop_count != genre_count: report['errors'].append('Prop/Genre record counts differ')
        if prop_count != idx_count: report['errors'].append('Prop/text record counts differ')
        if len(intid)//2 < prop_count: report['warnings'].append('IntID table shorter than Prop table')
        if prop:
            first=[struct.unpack_from('<II',prop,i*8) for i in range(prop_count)]
            ids=[a & 0x3fff for a,b in first if a]
            if len(ids)!=len(set(ids)): report['warnings'].append('Prop contains duplicate nonzero Konami IDs')
            report['counts']['propNonEmpty']=len(ids)
            for i,(word1,word2) in enumerate(first[:min(prop_count,10)]):
                if i and word1 and (word1&0x3fff)==0: report['warnings'].append(f'Prop record {i} has zero Konami ID')
        if idx:
            offsets=struct.unpack('<%dI'%(len(idx)//4),idx); report['counts']['textOffsets']=len(offsets)
            for lang in ['E','F','G','I','J','R','S']:
                nb=require(f'CARD_Name_{lang}.bin'); db=require(f'CARD_Desc_{lang}.bin'); ib=require(f'CARD_Indx_{lang}.bin')
                if not ib: continue
                if len(ib)!=len(idx): report['warnings'].append(f'CARD_Indx_{lang} size differs from E')
                off=struct.unpack('<%dI'%(len(ib)//4),ib)
                valid=0
                for j in range(min(len(off)//2-1,prop_count)):
                    n=text_at(nb,off[2*j]) if nb else None; d=text_at(db,off[2*j+1]) if db else None
                    if n is not None: valid+=1
                    if n is None or d is None: report['errors'].append(f'bad {lang} text offset at record {j}'); break
                report['counts'][f'{lang}Names']=valid
        # ensure image names are numeric JPGs
        bad_images=[n for n in names if n.lower().endswith('.jpg') and not Path(n).stem.isdigit()]
        if bad_images: report['warnings'].append(f'{len(bad_images)} JPG names are not numeric')
    report['ok']=not report['errors']; a.report.parent.mkdir(parents=True,exist_ok=True); a.report.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8'); print(json.dumps(report,ensure_ascii=False,indent=2)); raise SystemExit(0 if report['ok'] else 1)
if __name__=='__main__': main()

