import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class DiagnosticPhaseContractTests(unittest.TestCase):
    def test_bootstrap_and_first_frame_phases_are_logged(self):
        bootstrap = (ROOT / "NativeClient/patches/0001-bundled-game.patch").read_text(encoding="utf-8")
        game = (ROOT / "NativeClient/patches/0003-offline-ai.patch").read_text(encoding="utf-8")
        for token in ("DIAG phase=workdir.ready", "DIAG phase=edopro_main.enter", "DIAG phase=edopro_main.exit code={}"):
            self.assertIn(token, bootstrap)
        for token in ("DIAG phase=game.initialize.enter", "DIAG phase=game.initialize.settings", "DIAG phase=game.initialize.ui_ready", "DIAG phase=game.initialize.complete", "DIAG phase=mainloop.first_frame"):
            self.assertIn(token, game)


if __name__ == "__main__":
    unittest.main()
