import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class NativeCardVisualContractTests(unittest.TestCase):
    def test_card_face_has_frame_border_and_readable_minimums(self):
        source = (ROOT / "NativeClient/overlays/card-renderer/card_face.mm").read_text(encoding="utf-8")
        self.assertIn("void frameBorder", source)
        self.assertIn("CGContextStrokeRect(context, box({10, 10, 688, 996}))", source)
        self.assertIn("cardface::Title, 36, 24", source)
        self.assertIn("cardface::Description, 24, 18", source)
        self.assertIn("cardface::Statistics, 28, 22", source)


if __name__ == "__main__":
    unittest.main()

