import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class NativeVisualContractTests(unittest.TestCase):
    def test_card_effect_pulse_reuses_existing_motion_state(self):
        source = (ROOT / "NativeClient/patches/0005-duel-interface.patch").read_text(encoding="utf-8")
        self.assertIn("if(pcard->is_moving || pcard->is_fading ||", source)
        self.assertIn("pcard->aniFrame % 500", source)
        self.assertIn("std::sin", source)
        self.assertEqual(source.count("Moving cards receive a short cyan pulse"), 1)

    def test_campaign_nodes_have_neon_route_lock_and_portrait_hooks(self):
        source = (ROOT / "NativeClient/patches/0003-offline-ai.patch").read_text(encoding="utf-8")
        self.assertIn("campaignUnlocked = campaignui::LoadProgress", source)
        self.assertIn("routeLine->setOverrideColor(0xff27d9ff)", source)
        self.assertIn("campaignui::Load(\"./config/campaign-stages.json\")", source)
        self.assertIn("campaignCatalog[i].icon", source)
        self.assertIn("setUseAlphaChannel(true)", source)
        self.assertIn("LOCKED\\nStage", source)
        self.assertIn("campaignStage > mainGame->campaignUnlocked", source)


if __name__ == "__main__":
    unittest.main()
