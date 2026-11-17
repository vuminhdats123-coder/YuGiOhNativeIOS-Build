import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class NativeTypographyContractTests(unittest.TestCase):
    def test_ios_uses_readable_font_floor(self):
        source = (ROOT / "NativeClient/patches/0003-offline-ai.patch").read_text(encoding="utf-8")
        self.assertIn("textFontSize = std::max(textFontSize, 16)", source)
        self.assertIn("numFontSize = 20", source)
        self.assertIn("auxiliaryFontSize = 14", source)


if __name__ == "__main__":
    unittest.main()

