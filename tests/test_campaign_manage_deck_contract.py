import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class CampaignManageDeckContractTests(unittest.TestCase):
    def test_campaign_exposes_a_real_manage_deck_action(self):
        source = (ROOT / "NativeClient/patches/0003-offline-ai.patch").read_text(encoding="utf-8")
        enum = (ROOT / "NativeClient/patches/0007-mobile-shell-header.patch").read_text(encoding="utf-8")
        self.assertIn("btnCampaignDeck = env->addButton", source)
        self.assertIn("CAMPAIGN_DECK", source)
        self.assertIn("CAMPAIGN_DECK", enum)
        self.assertIn("mainGame->deckBuilder.Initialize();", source)


if __name__ == "__main__":
    unittest.main()
