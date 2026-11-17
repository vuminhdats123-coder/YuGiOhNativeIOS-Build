import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class NativeDuelMenuContractTests(unittest.TestCase):
    def test_duel_menu_uses_safe_touchable_button(self):
        source = (ROOT / "NativeClient/patches/0003-offline-ai.patch").read_text(encoding="utf-8")
        self.assertIn("env->addButton(Scale(900, 330, 1016, 400), nullptr, duelui::ControlsMenuID, L\"Menu\")", source)
        self.assertIn("IGUIButton* btnDuelTools", source)


if __name__ == "__main__":
    unittest.main()
