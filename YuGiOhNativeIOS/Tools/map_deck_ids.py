import json
from pathlib import Path
cards={x['sourceIndex']:x['name'] for x in json.loads(Path('YuGiOhNativeIOS/GeneratedData/cards-en.json').read_text(encoding='utf8'))}
idx=json.loads(Path('YuGiOhNativeIOS/GeneratedData/card-index.json').read_text(encoding='utf8'))
decks=json.loads(Path('YuGiOhNativeIOS/GeneratedData/ydc-decks.json').read_text(encoding='utf8'))
mapping={str(x['propFirst']&0x3fff):cards[x['sourceIndex']] for x in idx if x['sourceIndex'] in cards and x['propFirst']}
Path('YuGiOhNativeIOS/GeneratedData/card-id-names.json').write_text(json.dumps(mapping,ensure_ascii=False,separators=(',',':')),encoding='utf8')
used=sorted({i for d in decks for g in ('main','extra','side') for i in d[g]}); missing=[i for i in used if str(i) not in mapping]
report={'decks':len(decks),'usedKonamiIds':len(used),'mapped':len(used)-len(missing),'missing':missing[:200],'missingCount':len(missing)}
Path('YuGiOhNativeIOS/GeneratedData/deck-id-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8'); print(json.dumps(report,ensure_ascii=False,indent=2))
