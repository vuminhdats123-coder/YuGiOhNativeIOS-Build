import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class NativeVictoryOverlayContractTests(unittest.TestCase):
    def test_existing_edopro_victory_animation_and_reason_are_preserved(self):
        duel = (ROOT / "NativeClient/edopro/gframe/duelclient.cpp").read_text(encoding="utf-8")
        drawing = (ROOT / "NativeClient/edopro/gframe/drawing.cpp").read_text(encoding="utf-8")
        self.assertIn("case MSG_WIN:", duel)
        self.assertIn("mainGame->showcard = 101;", duel)
        self.assertIn("mainGame->dInfo.vic_string", duel)
        self.assertIn("case 101:", drawing)
        self.assertIn("dInfo.vic_string.size()", drawing)


if __name__ == "__main__":
    unittest.main()
