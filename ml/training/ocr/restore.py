"""Restore the pinned, public training source and checkpoint; never read patient data."""

import argparse
import hashlib
import json
import subprocess
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def valid(path, pin):
    if not path.is_file() or path.stat().st_size != pin["checkpoint_bytes"]:
        return False
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest() == pin["checkpoint_sha256"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    pin = json.loads((ROOT / "ml/registry/ocr-base.json").read_text())
    source = ROOT / ".local/upstream/PaddleOCR"
    if not source.exists():
        if args.offline:
            raise ValueError("Pinned PaddleOCR source is missing")
        source.mkdir(parents=True)
        subprocess.run(["git", "init", str(source)], check=True)
        subprocess.run(
            ["git", "-C", str(source), "remote", "add", "origin", pin["upstream"]], check=True
        )
        subprocess.run(
            ["git", "-C", str(source), "fetch", "--depth", "1", "origin", pin["revision"]],
            check=True,
        )
        subprocess.run(
            [
                "git",
                "-C",
                str(source),
                "sparse-checkout",
                "set",
                "ppocr",
                "tools",
                "configs/rec/PP-OCRv6",
            ],
            check=True,
        )
        subprocess.run(["git", "-C", str(source), "checkout", "--detach", "FETCH_HEAD"], check=True)
    revision = subprocess.check_output(
        ["git", "-C", str(source), "rev-parse", "HEAD"], text=True
    ).strip()
    if revision != pin["revision"]:
        raise ValueError("Existing source has a different revision; preserved without modification")
    subprocess.run(["git", "-C", str(source), "diff", "HEAD", "--quiet"], check=True)
    target = ROOT / ".local/models/ocr/PP-OCRv6_small_rec_pretrained.pdparams"
    if not valid(target, pin):
        if args.offline:
            raise ValueError("Pinned OCR training checkpoint is missing or corrupt")
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_suffix(target.suffix + ".part")
        with urllib.request.urlopen(pin["checkpoint_url"], timeout=120) as response:
            with temporary.open("wb") as output:
                while block := response.read(1024 * 1024):
                    output.write(block)
        if not valid(temporary, pin):
            raise ValueError(
                "Training checkpoint checksum/size mismatch; existing checkpoint preserved"
            )
        temporary.replace(target)
    print("Verified pinned PP-OCRv6 Small training source and checkpoint")


if __name__ == "__main__":
    main()
