import json
from pathlib import Path
rows=json.loads(Path('YuGiOhNativeIOS/GeneratedData/card-index.json').read_text(encoding='utf-8'))
assert len(rows)==7581
sample=rows[1]
assert sample['propFirst'] & 0x3FFF == 3900
assert sample['kind']=='Token' and sample['attribute']=='EARTH' and sample['race']=='Insect' and sample['level']==1
assert 'Token' in sample['genres']
print('card field verification passed:', sample['kind'], sample['attribute'], sample['race'], sample['level'], sample['genres'])
