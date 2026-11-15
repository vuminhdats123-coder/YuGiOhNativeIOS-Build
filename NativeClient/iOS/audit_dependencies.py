"""Read-only ar/Mach-O inventory for pinned iPhoneOS static dependencies.

Does not load a native library or execute its code, lipo, linker, or compiler.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import struct

ARCHIVE_SHA256 = "e4bb78cea762d674ff0499faa18870473e9a305d88e77ac812d35b2e3a7b9a89"
REQUIRED_LIBS = {"Irrlicht", "sqlite3", "event", "event_pthreads", "git2", "ssh2", "ssl", "crypto", "fmt", "curl", "freetype", "png", "bz2", "jpeg", "z"}


def inspect_archive(raw: bytes) -> dict:
    if not raw.startswith(b"!<arch>\n"):
        raise ValueError("Expected a plain static ar archive")
    cursor, members, versions = 8, 0, set()
    while cursor < len(raw):
        header = raw[cursor:cursor + 60]
        if len(header) != 60 or header[58:] != b"`\n":
            raise ValueError("Malformed ar member header")
        size = int(header[48:58].strip())
        data = raw[cursor + 60:cursor + 60 + size]
        if size < 0 or len(data) != size:
            raise ValueError("Truncated ar member")
        cursor += 60 + size + (size % 2)
        name = header[:16].rstrip(b" /")
        if name.startswith(b"#1/"):
            name_size = int(name[3:])
            if name_size > len(data):
                raise ValueError("Truncated extended ar filename")
            name, data = data[:name_size].rstrip(b"\x00"), data[name_size:]
        if name.startswith(b"__.SYMDEF") or name in (b"", b"/", b"//"):
            continue
        if len(data) < 32 or data[:4] != b"\xcf\xfa\xed\xfe":
            raise ValueError(f"Member is not little-endian 64-bit Mach-O: {name!r}")
        _, cpu, _, filetype, ncmds, sizeofcmds, _, _ = struct.unpack_from("<8I", data)
        if cpu != 0x0100000C or filetype != 1:
            raise ValueError(f"Member is not an arm64 MH_OBJECT: {name!r}")
        if sizeofcmds > len(data) - 32:
            raise ValueError("Truncated Mach-O commands")
        position, platform = 32, None
        for _ in range(ncmds):
            if position + 8 > 32 + sizeofcmds:
                raise ValueError("Invalid Mach-O command count")
            command, length = struct.unpack_from("<II", data, position)
            if length < 8 or position + length > 32 + sizeofcmds:
                raise ValueError("Invalid Mach-O command size")
            if command == 0x32:  # LC_BUILD_VERSION: platform iOS=2, simulator=7.
                if length < 24:
                    raise ValueError("Truncated LC_BUILD_VERSION")
                platform, minimum, sdk = struct.unpack_from("<III", data, position + 8)
                if platform != 2:
                    raise ValueError("Dependency member targets a different Apple platform")
                versions.add((minimum, sdk))
            elif command == 0x25:  # LC_VERSION_MIN_IPHONEOS; arm64 before arm64 simulator existed.
                if length < 16:
                    raise ValueError("Truncated LC_VERSION_MIN_IPHONEOS")
                minimum, sdk = struct.unpack_from("<II", data, position + 8)
                platform = 2
                versions.add((minimum, sdk))
            position += length
        if platform != 2:
            raise ValueError(f"No iPhoneOS platform evidence for {name!r}")
        members += 1
    if not members:
        raise ValueError("Static archive contains no Mach-O objects")
    def version(value):
        return f"{value >> 16}.{(value >> 8) & 255}.{value & 255}"
    return {"objects": members, "architecture": "arm64", "platform": "iPhoneOS",
            "versions": [{"minimum": version(m), "sdk": version(s)} for m, s in sorted(versions)]}


def audit(root: Path, archive: Path) -> dict:
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if digest != ARCHIVE_SHA256:
        raise ValueError("Dependency archive SHA256 differs from the pinned release")
    triplet = root / "installed/arm64-ios"
    if not (triplet / "include/irrlicht/irrlicht.h").is_file():
        raise ValueError("Expected vcpkg installed/arm64-ios headers")
    if not REQUIRED_LIBS <= {p.stem.removeprefix("lib") for p in (triplet / "lib").glob("*.a")}:
        raise ValueError("Required release libraries are missing")
    libraries = {}
    for folder in ("lib", "debug/lib"):
        for path in sorted((triplet / folder).glob("*.a")):
            if path.is_symlink():
                raise ValueError("Unexpected dependency symlink")
            raw = path.read_bytes()
            libraries[path.relative_to(root).as_posix()] = {
                "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest(), **inspect_archive(raw)}
    return {"archiveSHA256": digest, "libraries": libraries, "libraryCount": len(libraries),
            "objectCount": sum(item["objects"] for item in libraries.values()),
            "runtimeOrLinkCompatibilityVerified": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    result = audit(args.root, args.archive)
    args.report.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k != "libraries"}))


if __name__ == "__main__":
    main()
