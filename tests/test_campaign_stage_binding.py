from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class CampaignStageBindingTests(unittest.TestCase):
    def test_campaign_uses_catalog_deck_and_normalizes_distribution_names(self):
        source = (ROOT / 'NativeClient/patches/0003-offline-ai.patch').read_text(encoding='utf-8')
        self.assertIn('campaignCatalog[mainGame->campaignStage - 1].deckKey', source)
        self.assertIn('normalizeDeckKey', source)
        self.assertIn('value.rfind("OBB_", 0)', source)
        self.assertIn('value.rfind(\'_\')', source)

if __name__ == '__main__':
    unittest.main()
