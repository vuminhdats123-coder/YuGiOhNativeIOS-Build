import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class NativeLocaleContractTests(unittest.TestCase):
    def test_vietnamese_locale_is_visible_and_loaded_from_payload(self):
        patch = (ROOT / "NativeClient/patches/0003-offline-ai.patch").read_text(encoding="utf-8")
        self.assertIn('locale == EPRO_TEXT("vi-obb")', patch)
        self.assertIn('Tiếng Việt', patch)
        self.assertIn('config/languages/{}', patch)
        source = (ROOT / "NativeClient/edopro/gframe/game.cpp").read_text(encoding="utf-8")
        self.assertIn("LoadLocaleDB", source)


if __name__ == "__main__":
    unittest.main()
