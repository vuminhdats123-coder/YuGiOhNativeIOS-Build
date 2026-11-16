import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class SurrenderDeckTouchContractTests(unittest.TestCase):
    def test_player_deck_touch_opens_duel_controls_only_without_selection(self):
        source = (ROOT / "NativeClient/patches/0004-touch-menu.patch").read_text(encoding="utf-8")
        self.assertIn("hovered_location == LOCATION_DECK && hovered_controler == 0", source)
        self.assertIn("!mainGame->wCardSelect->isVisible()", source)
        self.assertIn("!mainGame->wCardDisplay->isVisible()", source)
        self.assertIn("mainGame->wDuelTools->setVisible(true)", source)


if __name__ == "__main__":
    unittest.main()
