import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class NativeOfflineResultPanelContractTests(unittest.TestCase):
    def test_offline_result_keeps_reason_lp_and_actions(self):
        source = (ROOT / "NativeClient/patches/0003-offline-ai.patch").read_text(encoding="utf-8")
        for token in (
            "offlineResultText = mainGame->dInfo.vic_string",
            "offlineResultLP[0]",
            "offlineResultLP[1]",
            "stOfflineResult->setText",
            "btnOfflineStart->setText(L\"New duel\")",
            "btnOfflineBack->setText(L\"Main menu\")",
        ):
            self.assertIn(token, source)


if __name__ == "__main__":
    unittest.main()
