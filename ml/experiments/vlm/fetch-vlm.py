"""Fetch pinned development-only checkpoints. Never downloads document content.

PaddleOCR-VL-1.6 is converted locally using the pinned runtime converter. Files
without upstream SHA256 are hashed into the private conversion manifest after
fetching from their immutable revision. No downloaded Python model code is run.
"""

import argparse
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def fetch(lock, destination):
    for candidate in lock["candidates"]:
        directory = destination / candidate["id"]
        directory.mkdir(parents=True, exist_ok=True)
        verified = []
        for item in candidate["files"]:
            name = item["path"]
            if Path(name).name != name:
                raise ValueError("Unsafe checkpoint path")
            target = directory / name

            def valid(path):
                if not path.is_file() or path.stat().st_size != item["bytes"]:
                    return False
                with path.open("rb") as source:
                    return (
                        not item["sha256"]
                        or hashlib.file_digest(source, "sha256").hexdigest() == item["sha256"]
                    )

            if not valid(target):
                partial = target.with_suffix(target.suffix + ".part")
                subprocess.run(
                    [
                        "curl",
                        "--fail",
                        "--location",
                        "--retry",
                        "2",
                        "--continue-at",
                        "-",
                        f"https://huggingface.co/{candidate['repository']}/resolve/{candidate['revision']}/{name}?download=true",
                        "--output",
                        str(partial),
                    ],
                    check=True,
                )
                if not valid(partial):
                    raise ValueError(f"Checkpoint integrity failed: {name}")
                partial.replace(target)
            with target.open("rb") as source:
                checksum = hashlib.file_digest(source, "sha256").hexdigest()
            verified.append({"path": name, "sha256": checksum, "bytes": target.stat().st_size})
        (directory / "source-manifest.json").write_text(
            json.dumps({**candidate, "files": verified}, indent=2) + "\n"
        )


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--destination", type=Path, default=ROOT / ".local/models/runtime/experiments/checkpoints"
    )
    a = p.parse_args()
    fetch(
        json.loads((ROOT / "ml/registry/runtime/vlm-experiments.lock.json").read_text()),
        a.destination,
    )
