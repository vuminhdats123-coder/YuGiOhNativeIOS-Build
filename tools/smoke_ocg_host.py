"""Verify the pinned official host DLL before any native smoke execution. Never builds or loads it."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import platform
import struct
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
SOURCE_REVISION = "fd2a557167f9e0fe19b867c325e67a3b3f9dca11"
IOS_CORE_REVISION = "46779fbe40e6a9bd8967f5dc6a03f4eaa6550d57"
BINARY_REPO_REVISION = "a2d0ff9f28a184a572d4c5ae60f57e2e8343c820"
URL = f"https://raw.githubusercontent.com/ProjectIgnis/bin/{BINARY_REPO_REVISION}/ocgcore.dll"
EXPECTED_SIZE = 1_881_102
EXPECTED_GIT_BLOB_SHA1 = "7abbcd82940f22504c5dd8c59c848c5ff36f7db5"
DEFAULT_DLL = ROOT / "outputs/ocg-reference/ocgcore-fd2a557.dll"
DEFAULT_REPORT = ROOT / "NativeClient/host-smoke.json"


def verify_binary(data: bytes) -> dict:
    blob_hash = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
    if len(data) != EXPECTED_SIZE or blob_hash != EXPECTED_GIT_BLOB_SHA1:
        raise ValueError("DLL size or pinned Git blob hash does not match; do not load this binary")
    return {"size": len(data), "gitBlobSHA1": blob_hash, "sha256": hashlib.sha256(data).hexdigest()}


def inspect_pe(data: bytes) -> dict:
    def unpack(fmt: str, offset: int):
        size = struct.calcsize(fmt)
        if offset < 0 or offset + size > len(data):
            raise ValueError("Truncated PE structure")
        return struct.unpack_from(fmt, data, offset)

    if data[:2] != b"MZ":
        raise ValueError("Not a PE image")
    pe = unpack("<I", 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError("Invalid PE signature")
    machine, section_count = unpack("<HH", pe + 4)
    optional_size = unpack("<H", pe + 20)[0]
    optional = pe + 24
    magic = unpack("<H", optional)[0]
    if magic not in (0x10B, 0x20B):
        raise ValueError("Unsupported PE optional header")
    directory_base = optional + (96 if magic == 0x10B else 112)
    directory_count = unpack("<I", directory_base - 4)[0]
    if directory_base > optional + optional_size or optional + optional_size > len(data):
        raise ValueError("Invalid PE optional header size")
    header_size = unpack("<I", optional + 60)[0]
    sections = []
    for index in range(section_count):
        entry = optional + optional_size + index * 40
        unpack("<40s", entry)
        virtual_size, address, raw_size, raw_pointer = unpack("<IIII", entry + 8)
        sections.append((address, virtual_size, raw_pointer, raw_size))

    def file_offset(rva: int) -> int:
        if 0 <= rva < min(header_size, len(data)):
            return rva
        for address, virtual_size, raw_pointer, raw_size in sections:
            if address <= rva < address + max(virtual_size, raw_size):
                delta = rva - address
                if delta >= raw_size or raw_pointer + delta >= len(data):
                    raise ValueError("PE RVA has no file-backed bytes")
                return raw_pointer + delta
        raise ValueError("PE RVA outside all sections")

    imports = []
    if directory_count >= 2:
        if directory_base + 16 > optional + optional_size:
            raise ValueError("Missing import directory header")
        import_rva, import_size = unpack("<II", directory_base + 8)
        if import_rva:
            terminated = False
            for relative in range(0, min(import_size, 20 * 256), 20):
                if relative + 20 > import_size:
                    break
                row = unpack("<IIIII", file_offset(import_rva + relative))
                if not any(row):
                    terminated = True
                    break
                name_offset = file_offset(row[3])
                end = data.find(b"\0", name_offset, name_offset + 260)
                if end < 0:
                    raise ValueError("Unterminated PE import name")
                imports.append(data[name_offset:end].decode("ascii"))
            if not terminated:
                raise ValueError("Unterminated PE import table")
    return {"machine": f"0x{machine:04x}", "architecture": {0x14C: "x86", 0x8664: "x64", 0xAA64: "arm64"}.get(machine, "unknown"),
            "bits": 32 if magic == 0x10B else 64, "imports": imports}


def compatibility(pe: dict, *, host_system: str, host_machine: str, pointer_bits: int) -> tuple[str, str]:
    expected_machine = {"AMD64": "x64", "X86_64": "x64", "X86": "x86", "I386": "x86", "I686": "x86", "ARM64": "arm64", "AARCH64": "arm64"}.get(host_machine.upper())
    if host_system != "Windows":
        return "blocked_platform", "This candidate is a Windows DLL."
    if pe["bits"] != pointer_bits or pe["architecture"] != expected_machine:
        return "blocked_architecture", "DLL architecture does not match this host process; no native load attempted."
    return "preflight_only", "Architecture matches; native execution is a separate, unperformed isolated smoke step."


def inspect_candidate(path: Path) -> dict:
    data = path.read_bytes()
    hashes = verify_binary(data)
    pe = inspect_pe(data)
    host = {"system": platform.system(), "machine": platform.machine(), "pointerBits": struct.calcsize("P") * 8}
    status, reason = compatibility(pe, host_system=host["system"], host_machine=host["machine"], pointer_bits=host["pointerBits"])
    return {
        "status": status, "reason": reason, "sourceURL": URL,
        "binaryRepositoryRevision": BINARY_REPO_REVISION, "binarySourceRevision": SOURCE_REVISION,
        "iosCoreRevision": IOS_CORE_REVISION, "exactIOSRevisionBinary": False,
        "provenanceNote": "Official bin commit labels fd2a557. Comparing it with 46779fbe changes build/deploy files only; this is not proof of the exact iOS build.",
        "hashes": hashes, "pe": pe, "host": host,
        "nativeLibraryLoaded": False, "nativeAPIVersion": None,
        "dependencyLoadChecked": False, "duelCreated": False, "cardScriptsExecuted": False,
        "buildTriggered": False, "iosRuntimeVerified": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dll", type=Path, default=DEFAULT_DLL)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--download", action="store_true", help="Download only the pinned public candidate if absent")
    args = parser.parse_args()
    try:
        if args.download and not args.dll.exists():
            with urllib.request.urlopen(URL, timeout=30) as response:
                data = response.read(EXPECTED_SIZE + 1)
            verify_binary(data)
            args.dll.parent.mkdir(parents=True, exist_ok=True)
            args.dll.write_bytes(data)
        report = inspect_candidate(args.dll)
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, indent=2))
    except (OSError, ValueError) as error:
        parser.exit(1, f"Host smoke refused: {error}\n")


if __name__ == "__main__":
    main()
