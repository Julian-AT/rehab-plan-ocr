#!/usr/bin/env python3
"""Fetch only pinned public speech assets; never access user data."""
import hashlib
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / "models/supertonic.lock.json").read_text())
target = root / "models/private/supertonic-3"
for entry in manifest["files"]:
    destination = target / entry["path"]
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and hashlib.sha256(destination.read_bytes()).hexdigest() == entry["sha256"]:
        continue
    temporary = destination.with_suffix(destination.suffix + ".download")
    url = f'https://huggingface.co/{manifest["model"]}/resolve/{manifest["revision"]}/{entry["path"]}'
    subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error", "--retry", "3", url, "--output", str(temporary)], check=True)
    if hashlib.sha256(temporary.read_bytes()).hexdigest() != entry["sha256"]:
        raise RuntimeError(f'Checksum mismatch: {entry["path"]}')
    temporary.replace(destination)
print("Verified bundled Supertonic 3 German voices")
