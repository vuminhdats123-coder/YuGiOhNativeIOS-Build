import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class NativeLobbyContractTests(unittest.TestCase):
    def test_lobby_art_avatar_and_icon_row_are_materialized(self):
        source = (ROOT / "NativeClient/patches/0003-offline-ai.patch").read_text(encoding="utf-8")
        for token in (
            "wMenuArt",
            "menuCardLeft",
            "menuCardRight",
            "menuPlayerAvatar",
            "GetTextureCard(4008",
            "GetTextureCard(4011",
            "menuIconButtons[4]",
            "imageManager.tSettings",
            "wMenuArt->setVisible",
        ):
            self.assertIn(token, source)


if __name__ == "__main__":
    unittest.main()
