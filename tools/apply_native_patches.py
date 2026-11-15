"""Apply the reviewed iOS bootstrap patch to the exact EDOPro revision. No builds."""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
PINNED_CLIENT_REVISION = "d0f111d6f3e0d4ee529b88a869ae0a971954bae3"
TARGET = "gframe/iOS/porting_ios.mm"
PATCH = ROOT / "NativeClient/patches/0001-bundled-game.patch"


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


def apply_native_patch(repo: Path, patch: Path = PATCH, *, expected_revision: str = PINNED_CLIENT_REVISION,
                       check_only: bool = False) -> str:
    repo, patch = repo.resolve(strict=True), patch.resolve(strict=True)
    patch_data = canonical(patch.read_bytes())
    headers = re.findall(rb"^diff --git a/(.+) b/(.+)$", patch_data, re.MULTILINE)
    if headers != [(TARGET.encode(), TARGET.encode())]:
        raise PatchError("Patch must modify only the reviewed iOS bootstrap file")
    if git(repo, "rev-parse", "HEAD").decode().strip() != expected_revision:
        raise PatchError("Client revision differs from the pinned revision; refusing to patch")
    if git(repo, "diff", "--cached", "--name-only").strip():
        raise PatchError("Client has staged edits; refusing to alter the checkout")
    status = git(repo, "status", "--porcelain", "--untracked-files=all", "--ignore-submodules=all")
    allowed = f" M {TARGET}"
    if any(line != allowed for line in status.decode("utf-8").splitlines()):
        raise PatchError("Client has unrelated edits or untracked files; refusing to patch")
    baseline = canonical(git(repo, "show", f"HEAD:{TARGET}"))

    # Recreate the expected file without touching the real checkout or its index.
    with tempfile.TemporaryDirectory(prefix="edopro-patch-") as temporary:
        fixture = Path(temporary).resolve()
        git(fixture, "init", "--quiet")
        target = fixture / TARGET
        target.parent.mkdir(parents=True)
        target.write_bytes(baseline)
        fixture_patch = fixture / "bootstrap.patch"
        fixture_patch.write_bytes(patch_data)
        git(fixture, "apply", "--check", str(fixture_patch))
        git(fixture, "apply", str(fixture_patch))
        expected = canonical(target.read_bytes())

    current = canonical((repo / TARGET).read_bytes())
    if current == expected:
        git(repo, "apply", "--reverse", "--check", str(patch))
        return "already-applied"
    if current != baseline:
        raise PatchError("Bootstrap file contains edits beyond the exact reviewed patch")
    if check_only:
        raise PatchError("Bootstrap patch has not been applied")
    git(repo, "apply", "--check", str(patch))
    git(repo, "apply", str(patch))
    if canonical((repo / TARGET).read_bytes()) != expected:
        raise PatchError("Patched file differs from the expected contents; inspect the checkout")
    return "applied"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=ROOT / "NativeClient/edopro")
    parser.add_argument("--check", action="store_true", help="Verify the exact patch is already applied; never edit the checkout")
    args = parser.parse_args()
    try:
        print(apply_native_patch(args.repo, check_only=args.check))
    except (PatchError, OSError) as error:
        parser.exit(1, f"Patch refused: {error}\n")


if __name__ == "__main__":
    main()
