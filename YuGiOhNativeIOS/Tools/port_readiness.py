"""Offline integration checks; does not compile Swift or dispatch a workflow."""
import json
from pathlib import Path
import plistlib
import re
import struct
import zipfile

from verify_duel_data import validate, require
from verify_obb_data import text_at

PROJECT = Path(__file__).resolve().parents[1]
ROOT = PROJECT.parent
GENERATED = PROJECT / 'GeneratedData'

def load(name):
    return json.loads((GENERATED / name).read_text(encoding='utf-8'))

def main():
    obb = ROOT / 'com.konami.ygodgtest/main.116.com.konami.ygodgtest.obb'
    data = validate(obb)
    project_text = (PROJECT / 'YuGiOhNativeIOS.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
    # This check covers this project's one-line PBX objects; it is not an Xcode project parser.
    objects = {}
    for key, body in re.findall(r'^\s*([A-F0-9]{24})(?: /\*.*?\*/)? = (.*);$', project_text, re.M):
        require(key not in objects, f'Duplicate PBX ID {key}')
        objects[key] = body
    def field(body, name):
        match = re.search(r'\b' + name + r' = ("[^"]*"|[^;]+);', body)
        return match.group(1).strip('"') if match else None
    parents = {}
    for key, body in objects.items():
        if field(body, 'isa') != 'PBXGroup':
            continue
        for child in re.findall(r'[A-F0-9]{24}', field(body, 'children') or ''):
            require(child in objects, f'Missing PBX child {child}')
            require(child not in parents, f'Multiple PBX parents for {child}')
            parents[child] = key
    def path_for(key):
        parent = path_for(parents[key]) if key in parents else PROJECT
        return (parent / (field(objects[key], 'path') or '')).resolve()
    resource_paths = {}
    for key, body in objects.items():
        if field(body, 'isa') == 'PBXFileReference' and field(body, 'sourceTree') == '<group>':
            path = path_for(key)
            if path.name == 'CardImages':
                continue  # Images are provided by the release asset at build time.
            require(path.exists(), f'PBX path does not exist: {path}')
            resource_paths[path.name] = path
        if field(body, 'isa') == 'PBXBuildFile':
            require(field(body, 'fileRef') in objects, 'Unresolved PBXBuildFile')
        if field(body, 'isa') in ('PBXSourcesBuildPhase', 'PBXResourcesBuildPhase'):
            for ref in re.findall(r'[A-F0-9]{24}', field(body, 'files') or ''):
                require(ref in objects and field(objects[ref], 'isa') == 'PBXBuildFile', f'Wrong build phase reference: {ref}')
    require(resource_paths.get('GeneratedData') == GENERATED.resolve(), 'GeneratedData not bundled from its real folder')
    for filename in ('offline-practice-decks.json', 'ydc-decks.json', 'card-id-names.json',
                     'card-relation-index.json', 'card-kana-index.json', 'card-pack-summary.json'):
        require((resource_paths['GeneratedData'] / filename).is_file(), f'Missing bundle data: {filename}')
    for source in (PROJECT / 'Sources').rglob('*.swift'):
        text = source.read_text(encoding='utf-8')
        require('`n' not in text and '\ufffd' not in text, f'Invalid text in {source.name}')
    relations = load('card-relations.json')
    with zipfile.ZipFile(obb) as z:
        language_counts = {}
        for lang in 'EFGIJKRS':
            offsets = list(struct.iter_unpack('<II', z.read(f'assets/CARD_Indx_{lang}.bin')))
            names = z.read(f'assets/CARD_Name_{lang}.bin')
            descriptions = z.read(f'assets/CARD_Desc_{lang}.bin')
            for n, d in offsets[:-1]:
                require(text_at(names, n) is not None and text_at(descriptions, d) is not None, f'Invalid {lang} text')
            language_counts[lang] = len(offsets) - 1
        for lang, values in relations['sort'].items():
            rank, order = values['rank'], values['order']
            require(sorted(order) == list(range(len(rank))), f'{lang} sort not permutation')
            require(all(rank[value] == pos for pos, value in enumerate(order)), f'{lang} inverse sort mismatch')
            for suffix, array in [('', rank), ('2', order)]:
                require(struct.pack(f'<{len(array)}H', *array) == z.read(f'assets/CARD_Sort{suffix}_{lang}.bin'), 'Sort source differs')
        fixed = list((GENERATED / 'plist-sanitized').glob('*.plist'))
        require(len(fixed) == 3, 'Missing fixed plists')
        for path in fixed:
            plistlib.loads(path.read_bytes())
        with zipfile.ZipFile(ROOT / 'card-images.zip') as images:
            jpgs = [name for name in z.namelist() if name.lower().endswith('.jpg')]
            for name in jpgs:
                image = images.getinfo('CardImages/' + Path(name).name)
                source = z.getinfo(name)
                require((image.CRC, image.file_size) == (source.CRC, source.file_size), f'Image mismatch: {name}')
    workflow = (ROOT / '.github/workflows/ios-build.yml').read_text(encoding='utf-8')
    require('workflow_dispatch:' in workflow and not re.search(r'^\s+(push|pull_request|schedule|workflow_run):', workflow, re.M), 'Unexpected automatic build trigger')
    report = {'offlineDataChecksPassed': True, 'catalogCards': data['catalogCards'],
              'ydcByteExactRoundTrips': data['ydcByteExactRoundTrips'], 'languagesValidated': language_counts,
              'bundledImagesMatchSourceCRC': len(jpgs), 'fixedPlistsParsed': len(fixed),
              'bundlePathsChecked': True, 'displayNameCoverage': 5215, 'sourceCardCoverage': 5213,
              'missingSourceDefinitions': [10855, 11766], 'manualBuildOnly': True,
              'engineBehaviorTests': 'authored; not executed', 'aiBehaviorTests': 'authored; not executed',
              'supportedEffectDefinitions': len(data['supportedEffectIdentities']),
              'supportedExtraDeckDefinitions': data['sourceEffectRegistryIdentityCheck']['extraDeckEntries'],
              'sourceEffectRegistryMatchesOBB': data['sourceEffectRegistryIdentityCheck']['matchesOBBWhitelist'],
              'swiftCompiled': False, 'iosBuildExecuted': False,
              'portComplete': False,
              'remaining': ['Run Swift behavioral self-checks when authorized', 'Validate UI on simulator/device when authorized',
                            'Other Effect Monsters and Extra Deck recipes', 'Flip/continuous effects and remaining Damage Step triggers',
                            'Xyz/Pendulum/Link and additional card effects', 'Campaign/online services']}
    (GENERATED / 'port-readiness.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))

if __name__ == '__main__':
    main()
