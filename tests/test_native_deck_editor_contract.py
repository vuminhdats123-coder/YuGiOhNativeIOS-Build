import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class NativeDeckEditorContractTests(unittest.TestCase):
    def test_deck_editor_neon_panel_and_live_counts(self):
        source = (ROOT / "NativeClient/patches/0003-offline-ai.patch").read_text(encoding="utf-8")
        counter = (ROOT / "NativeClient/patches/0006-deck-counter.patch").read_text(encoding="utf-8")
        for token in (
            "wDeckEdit->setBackgroundColor(0xe60a2a23)",
            "stDeckCount->setOverrideColor(0xff36d9ff)",
        ):
            self.assertIn(token, source)
        self.assertIn("RefreshDeckCounter();", counter)
        self.assertIn("Main {}/60  |  Extra {}/15  |  Side {}/15", counter)


if __name__ == "__main__":
    unittest.main()
