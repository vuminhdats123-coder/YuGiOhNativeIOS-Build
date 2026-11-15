import importlib.util
from pathlib import Path
import struct
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("ocg_host", ROOT / "tools/smoke_ocg_host.py")
smoke = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(smoke)


def pe_fixture(machine=0x14C, magic=0x10B):
    data = bytearray(1024)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 0x3C, 0x80)
    data[0x80:0x84] = b"PE\0\0"
    struct.pack_into("<HH", data, 0x84, machine, 1)
    optional_size = 224 if magic == 0x10B else 240
    struct.pack_into("<H", data, 0x94, optional_size)
    optional = 0x98
    struct.pack_into("<H", data, optional, magic)
    struct.pack_into("<I", data, optional + 60, 512)
    directory_base = optional + (96 if magic == 0x10B else 112)
    struct.pack_into("<I", data, directory_base - 4, 16)
    struct.pack_into("<II", data, directory_base + 8, 0x1000, 40)
    section = optional + optional_size
    struct.pack_into("<IIII", data, section + 8, 256, 0x1000, 256, 512)
    struct.pack_into("<IIIII", data, 512, 0, 0, 0, 0x1040, 0x1080)
    data[576:589] = b"KERNEL32.dll\0"
    return bytes(data)


class OCGHostPreflightTests(unittest.TestCase):
    def test_pe32_imports(self):
        result = smoke.inspect_pe(pe_fixture())
        self.assertEqual(result["architecture"], "x86")
        self.assertEqual(result["bits"], 32)
        self.assertEqual(result["imports"], ["KERNEL32.dll"])

    def test_pe64(self):
        result = smoke.inspect_pe(pe_fixture(0x8664, 0x20B))
        self.assertEqual(result["architecture"], "x64")
        self.assertEqual(result["bits"], 64)

    def test_x86_dll_rejected_for_x64_host(self):
        status, _ = smoke.compatibility(smoke.inspect_pe(pe_fixture()), host_system="Windows", host_machine="AMD64", pointer_bits=64)
        self.assertEqual(status, "blocked_architecture")

    def test_matching_host_still_does_not_claim_native_smoke(self):
        status, _ = smoke.compatibility(smoke.inspect_pe(pe_fixture()), host_system="Windows", host_machine="x86", pointer_bits=32)
        self.assertEqual(status, "preflight_only")

    def test_truncated_and_invalid_images(self):
        for data in (b"", b"MZ", pe_fixture()[:180], b"INVALID" + pe_fixture()[7:]):
            with self.assertRaises(ValueError):
                smoke.inspect_pe(data)

    def test_import_rva_out_of_bounds(self):
        data = bytearray(pe_fixture())
        struct.pack_into("<I", data, 512 + 12, 0x9000)
        with self.assertRaises(ValueError):
            smoke.inspect_pe(bytes(data))

    def test_wrong_hash_rejected_before_any_native_execution(self):
        with self.assertRaisesRegex(ValueError, "pinned Git blob hash"):
            smoke.verify_binary(pe_fixture())


if __name__ == "__main__":
    unittest.main()
