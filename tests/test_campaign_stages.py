import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("verify_campaign_stages", ROOT / "tools/verify_campaign_stages.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CampaignStageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="campaign-stages-")
        self.root = Path(self.temp.name)
        self.stage_path = self.root / "campaign-stages.json"
        self.catalog_path = self.root / "duel-portraits.json"
        self.portraits = self.root / "portraits"
        self.portraits.mkdir()
        self.stage = {
            "schemaVersion": 1,
            "stages": [{"id": 1, "chapter": 1, "node": 1, "title": "Haga",
                         "deckKey": "deck-a", "icon": "haga.png", "unlockAfterWins": 0}],
        }
        self.catalog = {"schemaVersion": 1, "decks": {"deck-a": {"icon": "haga.png", "displayName": "Haga"}}}
        self.stage_path.write_text(json.dumps(self.stage), encoding="utf-8")
        self.catalog_path.write_text(json.dumps(self.catalog), encoding="utf-8")
        (self.portraits / "haga.png").write_bytes(b"png")
        self.addCleanup(self.temp.cleanup)

    def test_valid_mapping(self):
        self.assertEqual(module.validate(self.stage_path, self.catalog_path, self.portraits), [])

    def test_rejects_unknown_deck_and_missing_icon(self):
        self.stage["stages"][0]["deckKey"] = "missing"
        self.stage_path.write_text(json.dumps(self.stage), encoding="utf-8")
        errors = module.validate(self.stage_path, self.catalog_path, self.portraits)
        self.assertTrue(any("portrait catalog" in error for error in errors))

    def test_rejects_non_monotonic_unlocks(self):
        self.stage["stages"] = [self.stage["stages"][0], dict(self.stage["stages"][0], id=2, title="Second", unlockAfterWins=-1)]
        self.stage_path.write_text(json.dumps(self.stage), encoding="utf-8")
        self.assertTrue(any("unlockAfterWins" in error for error in module.validate(self.stage_path, self.catalog_path, self.portraits)))


if __name__ == "__main__":
    unittest.main()
