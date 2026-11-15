import json
from pathlib import Path
root=Path('YuGiOhNativeIOS'); report={'data':{},'resources':{},'workflow':{},'notPorted':[]}
obb=json.loads((root/'GeneratedData/obb-validation.json').read_text(encoding='utf8')); report['data']['obbValidation']=obb['ok']; report['data']['obbErrors']=obb['errors']; report['data']['plistWarnings']=obb['warnings']
decks=json.loads((root/'GeneratedData/deck-id-validation.json').read_text(encoding='utf8')); report['data']['deckCoverage']=decks['mapped']==decks['usedKonamiIds'] and decks['missingCount']==0
rel=json.loads((root/'GeneratedData/relation-validation.json').read_text(encoding='utf8')); report['data']['sortAllConsistent']=all(x['consistent'] for x in rel['sort'].values()); report['data']['relations']=rel
pack=json.loads((root/'GeneratedData/card-pack-summary.json').read_text(encoding='utf8')); report['data']['packStatus']=pack['status']
for f in ['Resources/cards_en.json','Resources/card-index.json','GeneratedData/card-relations.json','GeneratedData/card-id-names.json','GeneratedData/ydc-decks.json','GeneratedData/plist-sanitized/TempTutorial01_it.plist','GeneratedData/card-kana-index.json','GeneratedData/card-pass.json','GeneratedData/card-pack-summary.json','GeneratedData/card-aux-tables.json','GeneratedData/relation-validation.json']:
 report['resources'][f]=(root/f).exists()
workflow=Path('.github/workflows/ios-build.yml').read_text(encoding='utf8'); report['workflow']['manualOnly']='workflow_dispatch:' in workflow and '\n  push:' not in workflow
report['notPorted']=['Cocos2d-x duel engine','Konami online services/server protocol','native Android lib and proprietary effect runtime']
Path(root/'GeneratedData/port-readiness.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8'); print(json.dumps(report,ensure_ascii=False,indent=2))
