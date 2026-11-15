"""Pure protocol/provenance tests; these do not load a native DLL."""
import ctypes as C
import importlib.util
from pathlib import Path
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('ocg_matches',ROOT/'tools/run_ocg_matches.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class MatchHarnessTests(unittest.TestCase):
    def test_frame_sequence_preserves_message_and_payload(self):
        data=b'\x03\0\0\0\x05\x01\x01'+b'\x02\0\0\0\x28\x00'
        self.assertEqual(list(m.packets(data)),[(5,b'\1\1'),(40,b'\0')])
    def test_frame_rejects_zero_truncated_and_overrun(self):
        for data in (b'\0',b'\0\0\0\0',b'\3\0\0\0\5\1'):
            with self.subTest(data=data),self.assertRaises(ValueError): list(m.packets(data))
    def test_deck_keeps_sections_and_duplicate_card_instances(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'a.ydk';p.write_text('#main\n'+''.join(str(i//3+1)+'\n' for i in range(40))+'#extra\n44\n!side\n55\n')
            d=m.parse_deck(p);self.assertEqual(len(d['main']),40);self.assertEqual(d['main'][:3],[1,1,1]);self.assertEqual(d['extra'],[44]);self.assertEqual(d['side'],[55])
    def test_deck_rejects_wrong_size_and_nondecimal_code(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'a.ydk'
            for data in ('#main\n1\n','#main\n-1\n','#main\n1x\n'):
                p.write_text(data)
                with self.subTest(data=data),self.assertRaises(ValueError):m.parse_deck(p)
    def card(self,alias=0,kind=17):
        sets=(C.c_uint16*2)(0x1234,0)
        return m.Card(100,alias,sets,kind,4,1,1,1000,1000,0,0,0)
    def test_declarable_code_type_and_setcode(self):
        c=self.card();op=lambda x:x<<32
        self.assertTrue(m.declarable(c,[100,op(0x40000100)]))
        self.assertFalse(m.declarable(c,[101,op(0x40000100)]))
        self.assertTrue(m.declarable(c,[16,op(0x40000102)]))
        self.assertTrue(m.declarable(c,[0x1234,op(0x40000101)]))
        self.assertFalse(m.declarable(c,[0x2234,op(0x40000101)]))
    def test_declarable_alias_token_and_division_restrictions(self):
        op=lambda x:x<<32
        self.assertFalse(m.declarable(self.card(alias=123),[1]))
        self.assertTrue(m.declarable(self.card(alias=123),[op(0x40000014),1]))
        self.assertFalse(m.declarable(self.card(kind=0x4001),[1]))
        self.assertTrue(m.declarable(self.card(kind=0x4001),[op(0x40000015),1]))
        self.assertFalse(m.declarable(self.card(),[1,0,op(0x40000003)]))
        self.assertFalse(m.declarable(self.card(),[1,2]))
    def test_python_pin_matches_known_release(self):
        self.assertEqual(m.PYTHON_SHA256,'084b9eb24cb848605c895d05b738fbc2572efc8b4c18c415a824065864a2b853')
        self.assertTrue(m.PYTHON_URL.startswith('https://www.python.org/ftp/python/3.12.10/'))

if __name__=='__main__':unittest.main()
