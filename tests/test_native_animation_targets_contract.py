import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class NativeAnimationTargetsContractTests(unittest.TestCase):
    def test_summon_effect_attack_and_target_states_receive_motion_pulse(self):
        source = (ROOT / "NativeClient/patches/0005-duel-interface.patch").read_text(encoding="utf-8")
        self.assertIn("pcard->is_showtarget", source)
        self.assertIn("pcard->is_showchaintarget", source)
        self.assertIn("pcard->is_showequip", source)
        self.assertIn("pcard->cmdFlag & COMMAND_ATTACK", source)
        self.assertIn("0x5070ff", source)
        self.assertIn("0x50ff80", source)


if __name__ == "__main__":
    unittest.main()
