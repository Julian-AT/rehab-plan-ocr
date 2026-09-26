#!/usr/bin/env python3
"""Bundle pinned Martin weights, voice, tokenizer and local pronunciation data."""
import ast
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / "models/kokoro.lock.json").read_text())
target = ROOT / "models/private/kokoro-martin"
target.mkdir(parents=True, exist_ok=True)
entries = {entry["path"]: entry for entry in manifest["files"]}
def valid(path, name):
    return path.exists() and path.stat().st_size == entries[name]["bytes"] and hashlib.sha256(path.read_bytes()).hexdigest() == entries[name]["sha256"]
for name, remote in [("kokoro-martin.onnx", "kokoro-martin.onnx"), ("voices-martin.npz", "voices-martin.npz"), ("MODEL_CARD.md", "README.md")]:
    destination = target / name
    if valid(destination, name): continue
    temporary = destination.with_suffix(destination.suffix + ".download")
    subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error", "--retry", "3", "--retry-all-errors", "--max-time", "300", f'https://huggingface.co/{manifest["model"]}/resolve/{manifest["revision"]}/{remote}', "--output", str(temporary)], check=True)
    if not valid(temporary, name): raise RuntimeError(f"Checksum mismatch: {name}")
    temporary.replace(destination)
# Decode the pinned little-endian NumPy array without a NumPy build dependency.
with zipfile.ZipFile(target / "voices-martin.npz") as voices:
    raw = voices.read("martin.npy")
assert raw[:8] == b"\x93NUMPY\x01\x00", "Unexpected voice array format"
length = struct.unpack("<H", raw[8:10])[0]
header = ast.literal_eval(raw[10:10 + length].decode("ascii"))
assert header == {"descr": "<f4", "fortran_order": False, "shape": (510, 1, 256)}, "Unexpected Martin shape"
(target / "martin.f32").write_bytes(raw[10 + length:])
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
# Keep the embedded manifest with the bundle for packaging inspections.
shutil.copyfile(ROOT / "models/kokoro.lock.json", target / "manifest.json")
print(f"Verified {len(entries)} bundled Kokoro/Martin speech and pronunciation assets (24 kHz)")
