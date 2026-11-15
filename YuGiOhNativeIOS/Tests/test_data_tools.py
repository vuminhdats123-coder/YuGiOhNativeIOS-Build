"""Data regression checks only; this does not compile or run the duel engine."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / 'Tools'))
from verify_obb_data import text_at


class DataToolsTests(unittest.TestCase):
    def test_utf16_terminator_must_be_aligned(self):
        self.assertEqual(text_at('AB\0'.encode('utf-16le'), 0), 'AB')
        self.assertIsNone(text_at('A\0'.encode('utf-16le'), 1))

    def test_reject_invalid_or_unterminated_utf16(self):
        self.assertIsNone(text_at('A'.encode('utf-16le'), 0))
        self.assertIsNone(text_at(b'\x00\xd8\x00\x00', 0))

    def test_extractor_reproduces_bundled_catalog(self):
        obb = PROJECT.parent / 'com.konami.ygodgtest/main.116.com.konami.ygodgtest.obb'
        with tempfile.TemporaryDirectory(prefix='yugioh-data-') as directory:
            subprocess.run([sys.executable, str(PROJECT / 'Tools/extract_obb.py'),
                            str(obb), directory], check=True, capture_output=True)
            actual = json.loads((Path(directory) / 'cards-en.json').read_text(encoding='utf8'))
            expected = json.loads((PROJECT / 'Resources/cards_en.json').read_text(encoding='utf8'))
            self.assertEqual(actual, expected)
            self.assertEqual(len(list(Path(directory).glob('CARD_*.bin'))), 75)


if __name__ == '__main__':
    unittest.main()
