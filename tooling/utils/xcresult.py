"""Read XCTest bundles through verified disposable copies, retaining original evidence."""

import hashlib
import shutil
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path


def command(arguments):
    return subprocess.run(
        ["xcrun", "xcresulttool", *arguments],
        check=True,
        capture_output=True,
        text=True,
        timeout=120,
    ).stdout


def inventory(root):
    files = {}
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise ValueError("Result evidence must not contain symlinks")
        if path.is_file():
            with path.open("rb") as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
            files[str(path.relative_to(root))] = {"bytes": path.stat().st_size, "sha256": digest}
    return files


@contextmanager
def preserved_result(bundle):
    """xcresulttool can create a SQLite index even when asked only to read a bundle."""
    bundle = bundle.resolve(strict=True)
    if not bundle.is_dir():
        raise ValueError("Source result bundle must be a directory")
    original = inventory(bundle)
    if not original:
        raise ValueError("Source result bundle is empty")
    try:
        with tempfile.TemporaryDirectory(prefix="reha-xcresult-") as temporary:
            working = Path(temporary) / "result.xcresult"
            if sys.platform == "darwin":
                subprocess.run(["cp", "-cRp", str(bundle), str(working)], check=True, timeout=120)
            else:
                shutil.copytree(bundle, working)
            if inventory(working) != original:
                raise ValueError("Result working copy does not match the source")
            yield working, original
    finally:
        if inventory(bundle) != original:
            raise ValueError("Source result bundle changed while collecting evidence")
