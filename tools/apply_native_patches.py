"""Materialize reviewed patches/overlays on the exact EDOPro revision. No builds."""
from __future__ import annotations

import argparse
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
PINNED_CLIENT_REVISION = "d0f111d6f3e0d4ee529b88a869ae0a971954bae3"
TARGET = "gframe/iOS/porting_ios.mm"
PATCH = ROOT / "NativeClient/patches/0001-bundled-game.patch"
SERIES = ROOT / "NativeClient/patches/series.json"


class PatchError(RuntimeError):
    pass


def git(repo: Path, *arguments: str) -> bytes:
    result = subprocess.run(["git", "-C", str(repo), *arguments], capture_output=True, check=False)
    if result.returncode:
        raise PatchError(result.stderr.decode("utf-8", errors="replace").strip() or "Git operation failed")
    return result.stdout


def canonical(data: bytes) -> bytes:
    # Git checkouts may use CRLF on Windows; only line-ending differences are ignored.
    return data.replace(b"\r\n", b"\n")


def safe_path(root: Path, relative: str) -> Path:
    value = PurePosixPath(relative)
    if (not relative or value.is_absolute() or value.as_posix() != relative
            or any(part in ("..", ".git") for part in value.parts)
            or any(char in relative for char in ("\\", ":", "\0")) or relative == "."):
        raise PatchError(f"Unsafe integration path: {relative!r}")
    current = root
    for part in value.parts:
        current /= part
        if current.is_symlink() or getattr(current, "is_junction", lambda: False)():
            raise PatchError(f"Linked integration path: {relative}")
    return current


def materialize(repo: Path, specs, overlays, *, expected_revision: str, check_only: bool) -> str:
    repo = repo.resolve(strict=True)
    if git(repo, "rev-parse", "HEAD").decode().strip() != expected_revision:
        raise PatchError("Client revision differs from the pinned revision; refusing to patch")
    if git(repo, "diff", "--cached", "--name-only").strip():
        raise PatchError("Client has staged edits; refusing to alter the checkout")
    patch_data, targets = [], set()
    for patch, reviewed in specs:
        data = canonical(Path(patch).read_bytes())
        headers = re.findall(rb"^diff --git a/(.+) b/(.+)$", data, re.MULTILINE)
        actual = [left.decode("utf-8") for left, right in headers if left == right]
        if (len(actual) != len(headers) or len(actual) != len(set(actual)) or set(actual) != set(reviewed)):
            raise PatchError("Patch must modify only its explicitly reviewed target files")
        if targets.intersection(actual):
            raise PatchError("Multiple patches target the same file; combine the reviewed diff")
        for relative in actual:
            safe_path(repo, relative)
        targets.update(actual)
        patch_data.append(data)
    if targets.intersection(overlays):
        raise PatchError("An overlay cannot replace a patched upstream file")
    for relative in overlays:
        safe_path(repo, relative)
    allowed = targets | set(overlays)
    modified = git(repo, "diff", "--name-only", "-z", "--ignore-submodules=all").decode("utf-8").split("\0")
    untracked = git(repo, "ls-files", "--others", "--exclude-standard", "-z").decode("utf-8").split("\0")
    if any(path and path not in allowed for path in modified + untracked):
        raise PatchError("Client has unrelated edits or untracked files; refusing to patch")
    baseline = {path: canonical(git(repo, "show", f"HEAD:{path}")) for path in targets}
    for path in overlays:
        if git(repo, "ls-files", "--", path).strip():
            raise PatchError(f"Overlay would replace a tracked upstream file: {path}")

    # Reconstruct every expected file before changing any file in the user's checkout.
    with tempfile.TemporaryDirectory(prefix="edopro-patch-") as temporary:
        fixture = Path(temporary).resolve()
        git(fixture, "init", "--quiet")
        for relative, data in baseline.items():
            target = fixture / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        for index, data in enumerate(patch_data):
            fixture_patch = fixture / f"reviewed-{index}.patch"
            fixture_patch.write_bytes(data)
            git(fixture, "apply", "--check", str(fixture_patch))
            git(fixture, "apply", str(fixture_patch))
        expected = {path: canonical((fixture / path).read_bytes()) for path in targets}
    expected.update(overlays)
    changes = []
    for relative, data in expected.items():
        path = safe_path(repo, relative)
        if path.exists() and not path.is_file():
            raise PatchError(f"Integration target is not a regular file: {relative}")
        original = path.read_bytes() if path.is_file() else None
        current = canonical(original) if original is not None else None
        if current == data:
            continue
        if current != baseline.get(relative):
            raise PatchError(f"File contains edits beyond the exact reviewed integration: {relative}")
        changes.append((path, data, original))
    if check_only and changes:
        raise PatchError("Native integration has not been applied")
    if not changes:
        return "already-applied"
    completed = []
    try:
        for path, data, previous in changes:
            path.parent.mkdir(parents=True, exist_ok=True)
            completed.append((path, previous))
            path.write_bytes(data)
    except OSError:
        # Restore only files this operation changed; never delete a directory or unrelated data.
        for path, previous in reversed(completed):
            if previous is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(previous)
        raise
    return "applied"


def apply_native_patch(repo: Path, patch: Path = PATCH, *, expected_revision: str = PINNED_CLIENT_REVISION,
                       check_only: bool = False) -> str:
    return materialize(repo, [(patch, [TARGET])], {}, expected_revision=expected_revision, check_only=check_only)


def apply_native_integration(repo: Path, series: Path = SERIES, *, expected_revision: str = PINNED_CLIENT_REVISION,
                             check_only: bool = False) -> str:
    series = series.resolve(strict=True)
    native = series.parent.parent
    manifest = json.loads(series.read_text(encoding="utf-8-sig"))
    if manifest.get("schemaVersion") != 1:
        raise PatchError("Unsupported integration manifest version")
    specs = [(safe_path(native, row['file']), row['targets']) for row in manifest['patches']]
    overlays = {}
    for row in manifest['overlays']:
        if row['target'] in overlays:
            raise PatchError("Duplicate overlay destination")
        overlays[row['target']] = canonical(safe_path(native, row['source']).read_bytes())
    return materialize(repo, specs, overlays, expected_revision=expected_revision, check_only=check_only)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=ROOT / "NativeClient/edopro")
    parser.add_argument("--check", action="store_true", help="Verify the exact patch is already applied; never edit the checkout")
    args = parser.parse_args()
    try:
        print(apply_native_integration(args.repo, check_only=args.check))
    except (PatchError, OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"Patch refused: {error}\n")


if __name__ == "__main__":
    main()
