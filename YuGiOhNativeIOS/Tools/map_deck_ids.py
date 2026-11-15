"""Regenerate display names; external names do not make missing cards playable."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'GeneratedData'
# Name-only references, absent from the supplied CARD_Prop/IntID tables.
FALLBACKS = {'10855': 'Number 94: Crystalzero', '11766': 'Number S39: Utopia the Lightning'}
SOURCE = 'https://github.com/nzxth2/YGO_LOTD_LE_YDC_Converter/blob/master/src/cards.cpp'

def main():
    cards = {x['sourceIndex']: x['name'] for x in json.loads((ROOT / 'cards-en.json').read_text(encoding='utf8'))}
    metadata = json.loads((ROOT / 'card-index.json').read_text(encoding='utf8'))
    decks = json.loads((ROOT / 'ydc-decks.json').read_text(encoding='utf8'))
    mapping = {}
    for row in metadata:
        card_id = row['propFirst'] & 0x3fff
        if card_id and row['sourceIndex'] in cards:
            if str(card_id) in mapping:
                raise ValueError(f'Duplicate Konami ID {card_id}')
            mapping[str(card_id)] = cards[row['sourceIndex']]
    used = {card_id for deck in decks for group in ('main', 'extra', 'side') for card_id in deck[group]}
    absent = sorted(card_id for card_id in used if str(card_id) not in mapping)
    fallbacks = {key: name for key, name in FALLBACKS.items() if int(key) in absent}
    mapping.update(fallbacks)
    missing = sorted(card_id for card_id in used if str(card_id) not in mapping)
    report = {'decks': len(decks), 'usedKonamiIds': len(used), 'mapped': len(used) - len(missing),
              'missing': missing, 'missingCount': len(missing), 'missingSourceCardData': absent,
              'fallbackNames': fallbacks, 'fallbackSource': SOURCE, 'gameplayCoverageComplete': not absent}
    (ROOT / 'card-id-names.json').write_text(json.dumps(mapping, ensure_ascii=False, separators=(',', ':')), encoding='utf8')
    (ROOT / 'deck-id-validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
    print(json.dumps(report, ensure_ascii=False, indent=2))

if __name__ == '__main__':
    main()
