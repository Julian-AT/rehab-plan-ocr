"""Restore the pinned, public training source and checkpoint; never read patient data."""

import argparse
import fcntl
import hashlib
import json
import subprocess
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def valid(path, pin):
    if not path.is_file() or path.stat().st_size != pin["checkpoint_bytes"]:
        return False
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest() == pin["checkpoint_sha256"]


def download_checkpoint(response, target, pin):
    """Read at most the pinned size plus one byte, preserving the installed checkpoint."""
    expected = pin["checkpoint_bytes"]
    if type(expected) is not int or expected < 1:
        raise ValueError("Checkpoint restoration requires a positive pinned byte count")
    temporary = target.with_suffix(target.suffix + ".part")
    remaining = expected + 1
    with temporary.open("wb") as output:
        while remaining:
            block = response.read(min(1024 * 1024, remaining))
            if not block:
                break
            output.write(block)
            remaining -= len(block)
    if not valid(temporary, pin):
        raise ValueError(
            "Training checkpoint checksum/size mismatch; existing checkpoint preserved"
        )
    temporary.replace(target)


def verify_source(source, pin):
    revision = subprocess.check_output(
        ["git", "-C", str(source), "rev-parse", "HEAD"], text=True
    ).strip()
    if revision != pin["revision"]:
        raise ValueError("Existing source has a different revision; preserved without modification")
    subprocess.run(["git", "-C", str(source), "diff", "HEAD", "--quiet"], check=True)


def restore_source(source, pin, *, offline=False):
    if source.exists() or source.is_symlink():
        verify_source(source, pin)
        return
    if offline:
        raise ValueError("Pinned PaddleOCR source is missing")
    source.parent.mkdir(parents=True, exist_ok=True)
    # Cooperating restores serialize publication. An existing checkout is never reset.
    with (source.parent / f".{source.name}.restore.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if source.exists() or source.is_symlink():
            verify_source(source, pin)
            return
        staging = Path(tempfile.mkdtemp(prefix=f".{source.name}-restore-", dir=source.parent))
        try:
            subprocess.run(["git", "init", str(staging)], check=True)
            subprocess.run(
                ["git", "-C", str(staging), "remote", "add", "origin", pin["upstream"]], check=True
            )
            subprocess.run(
                ["git", "-C", str(staging), "fetch", "--depth", "1", "origin", pin["revision"]],
                check=True,
            )
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(staging),
                    "sparse-checkout",
                    "set",
                    "ppocr",
                    "tools",
                    "configs/rec/PP-OCRv6",
                ],
                check=True,
            )
            subprocess.run(
                ["git", "-C", str(staging), "checkout", "--detach", "FETCH_HEAD"], check=True
            )
            verify_source(staging, pin)
            if source.exists() or source.is_symlink():
                raise FileExistsError(f"Source appeared during restore; preserved: {source}")
            staging.rename(source)
        except BaseException as error:
            error.add_note(f"Unpublished restore checkout preserved at {staging}")
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    pin = json.loads((ROOT / "ml/registry/ocr-base.json").read_text())
    source = ROOT / ".local/upstream/PaddleOCR"
    restore_source(source, pin, offline=args.offline)
    target = ROOT / ".local/models/ocr/PP-OCRv6_small_rec_pretrained.pdparams"
    if not valid(target, pin):
        if args.offline:
            raise ValueError("Pinned OCR training checkpoint is missing or corrupt")
        target.parent.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(pin["checkpoint_url"], timeout=120) as response:
            download_checkpoint(response, target, pin)
    print("Verified pinned PP-OCRv6 Small training source and checkpoint")


if __name__ == "__main__":
    main()
