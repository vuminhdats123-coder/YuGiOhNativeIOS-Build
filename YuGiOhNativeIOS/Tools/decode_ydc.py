#!/usr/bin/env python3
import argparse,json,re,struct,zipfile
from pathlib import Path

def read_deck(data):
    if len(data)<14: raise ValueError('too short')
    unknown=struct.unpack_from('<Q',data,0)[0]; off=8; groups=[]
    for label in ('main','extra','side'):
        count=struct.unpack_from('<H',data,off)[0]; off+=2
        if off+count*2>len(data): raise ValueError(f'{label} exceeds file')
        ids=list(struct.unpack_from('<%dH'%count,data,off)) if count else []; off+=count*2; groups.append(ids)
    if off != len(data): raise ValueError(f'{len(data)-off} trailing bytes')
    return {'unknown':unknown,'main':groups[0],'extra':groups[1],'side':groups[2]}

def sanitize_xml(raw):
    # Preserve every byte except bare ampersands that make XML invalid.
    return re.sub(rb'&(?!amp;|lt;|gt;|quot;|apos;|#\d+;|#x[0-9A-Fa-f]+;)', b'&amp;', raw)

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('obb',type=Path); ap.add_argument('out',type=Path); a=ap.parse_args(); a.out.mkdir(parents=True,exist_ok=True)
    decks=[]; errors=[]
    with zipfile.ZipFile(a.obb) as z:
        for n in z.namelist():
            if not n.endswith('.ydc'): continue
            try: decks.append({'file':Path(n).name,**read_deck(z.read(n))})
            except Exception as e: errors.append({'file':n,'error':str(e)})
        plist_out=a.out/'plist-sanitized'; plist_out.mkdir(exist_ok=True)
        plist_errors=[]
        for n in ('assets/TempTutorial01_it.plist','assets/LocalizationGlossary40.plist','assets/LocalizationGlossary41.plist'):
            raw=z.read(n); fixed=sanitize_xml(raw); (plist_out/Path(n).name).write_bytes(fixed)
            plist_errors.append({'file':Path(n).name,'changedBytes':sum(x!=y for x,y in zip(raw,fixed))})
    (a.out/'ydc-decks.json').write_text(json.dumps(decks,ensure_ascii=False,separators=(',',':')),encoding='utf8')
    (a.out/'ydc-errors.json').write_text(json.dumps(errors,ensure_ascii=False,indent=2),encoding='utf8')
    (a.out/'plist-sanitized.json').write_text(json.dumps(plist_errors,ensure_ascii=False,indent=2),encoding='utf8')
    print(f'decoded {len(decks)} decks, errors {len(errors)}, sanitized {len(plist_errors)} plists')
    raise SystemExit(1 if errors else 0)
if __name__=='__main__': main()
