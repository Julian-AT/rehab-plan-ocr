#!/usr/bin/env python3
"""Bundle pinned German Victoria weights, voice and local pronunciation data."""
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / "models/kokoro.lock.json").read_text())
target = ROOT / "models/private" / manifest["bundle_directory"]
target.mkdir(parents=True, exist_ok=True)
entries = {entry["path"]: entry for entry in manifest["files"]}
def valid(path, name):
    return path.exists() and path.stat().st_size == entries[name]["bytes"] and hashlib.sha256(path.read_bytes()).hexdigest() == entries[name]["sha256"]
if not valid(target / "model.onnx", "model.onnx") or not valid(target / "voice.f32", "voice.f32"):
    subprocess.run(["uv", "run", "--locked", str(ROOT / "scripts/export-victoria.py")], check=True)
for name, entry in entries.items():
    if "remote" not in entry and "remote_url" not in entry: continue
    destination = target / name
    if valid(destination, name): continue
    temporary = destination.with_suffix(destination.suffix + ".download")
    subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error", "--retry", "3", "--retry-all-errors", "--max-time", "300", entry.get("remote_url") or f'https://huggingface.co/{manifest["model"]}/resolve/{manifest["revision"]}/{entry["remote"]}', "--output", str(temporary)], check=True)
    if not valid(temporary, name): raise RuntimeError(f"Checksum mismatch: {name}")
    temporary.replace(destination)
# The model's tokenizer must match the renderer's phoneme-to-token mapping.
expected_vocab = json.loads((ROOT / "models/kokoro-vocab.json").read_text())
model_vocab = json.loads((target / "config.json").read_text())["vocab"]
assert model_vocab == expected_vocab
raw = (target / "voice.f32").read_bytes()
assert len(raw) == 510 * 256 * 4, "Unexpected Victoria voice shape"
assert all(abs(v[0]) < float("inf") for v in struct.iter_unpack("<f", raw)), "Invalid voice values"
for source, name in [("models/kokoro-vocab.json", "vocab.json"), ("licenses/kokoro-apache-2.0.txt", "LICENSE"), ("licenses/kokoro-source.txt", "NOTICE")]:
    shutil.copyfile(ROOT / source, target / name)
data = ROOT / "models/private/espeak/host/espeak-ng-data"
if not (data / "de_dict").exists():
    subprocess.run(["python3", str(ROOT / "scripts/build-phonemizer.py"), "host"], check=True)
for name in entries:
    if name.startswith("espeak-ng-data/"):
        destination = target / name; destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(data / name.removeprefix("espeak-ng-data/"), destination)
for name in entries:
    if not valid(target / name, name): raise RuntimeError(f"Bundled speech asset checksum mismatch: {name}")
shutil.copyfile(ROOT / "models/kokoro.lock.json", target / "manifest.json")
print(f"Verified {len(entries)} bundled Kokoro/Victoria speech and pronunciation assets (24 kHz)")
