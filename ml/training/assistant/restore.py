"""Restore a revision-pinned Qwen checkpoint, or verify it without networking."""

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
REGISTRY = ROOT / "ml/registry/assistant-base.json"


def sha(path):
    with Path(path).open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def verify(path):
    registry = json.loads(REGISTRY.read_text())
    for name, expected in registry["files"].items():
        file = path / name
        if (
            not file.is_file()
            or file.stat().st_size != expected["bytes"]
            or sha(file) != expected["sha256"]
        ):
            raise ValueError(f"Missing or mismatched pinned assistant file: {name}")
    return registry


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    target = ROOT / ".local/models/assistant/qwen3-0.6b"
    registry = json.loads(REGISTRY.read_text())
    try:
        verify(target)
    except ValueError:
        if args.offline:
            raise
        from huggingface_hub import snapshot_download

        snapshot_download(
            registry["repository"],
            revision=registry["revision"],
            local_dir=target,
            allow_patterns=list(registry["files"]),
            max_workers=2,
        )
    verify(target)
    print(f"Verified {len(registry['files'])} pinned Qwen3-0.6B files")


if __name__ == "__main__":
    main()
