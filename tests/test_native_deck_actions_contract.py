import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class NativeDeckActionsContractTests(unittest.TestCase):
    def test_new_and_revert_are_real_deck_editor_actions(self):
        ui = (ROOT / "NativeClient/patches/0003-offline-ai.patch").read_text(encoding="utf-8")
        actions = (ROOT / "NativeClient/patches/0006-deck-counter.patch").read_text(encoding="utf-8")
        enum = (ROOT / "NativeClient/patches/0007-mobile-shell-header.patch").read_text(encoding="utf-8")
        self.assertIn("btnNewDeck = AlignElementWithParent", ui)
        self.assertIn("BUTTON_CLEAR_DECK, L\"New\"", ui)
        self.assertIn("btnRevertDeck = AlignElementWithParent", ui)
        self.assertIn("BUTTON_REVERT_DECK, L\"Revert\"", ui)
        self.assertIn("snapshot_deck = current_deck", actions)
        self.assertIn("case BUTTON_REVERT_DECK", actions)
        self.assertIn("current_deck = snapshot_deck", actions)
        self.assertIn("BUTTON_REVERT_DECK", enum)


if __name__ == "__main__":
    unittest.main()
