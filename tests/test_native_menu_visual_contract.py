import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class NativeMenuVisualContractTests(unittest.TestCase):
    def test_menu_has_readable_neon_shell_and_card_frames(self):
        source = (ROOT / "NativeClient/patches/0003-offline-ai.patch").read_text(encoding="utf-8")
        for token in (
            "menuBackdrop = env->addStaticText",
            "menuCardFrameLeft = env->addStaticText",
            "menuCardFrameRight = env->addStaticText",
            "menuBackdrop->setBackgroundColor(0xd9081026)",
            "wMainMenu->setDrawBackground(false)",
            "wMainMenu->setDraggable(false)",
        ):
            self.assertIn(token, source)


if __name__ == "__main__":
    unittest.main()

