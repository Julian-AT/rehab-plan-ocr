"""Read-only verification of all model/runtime assets needed by a native target."""

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TARGETS = {"simulator": "aarch64-apple-ios-sim", "device": "aarch64-apple-ios"}


def sha(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def pinned_file(path, entry):
    if not path.is_file() or path.stat().st_size != entry["bytes"] or sha(path) != entry["sha256"]:
        raise ValueError(
            f"Missing or corrupt native asset: {path}. Run make restore and make convert."
        )


def model_bundle(root, lock):
    if json.loads((root / "manifest.json").read_text()) != lock:
        raise ValueError(f"Bundled manifest differs from committed pins: {root}")
    for entry in lock["files"]:
        name = Path(entry["path"])
        if name.is_absolute() or ".." in name.parts:
            raise ValueError("Pinned bundle paths must be local")
        pinned_file(root / name, entry)
    if "dictionary_sha256" in lock and sha(root / "dictionary.json") != lock["dictionary_sha256"]:
        raise ValueError("Recognition dictionary differs from the deployment pin")


def verify(root, targets):
    registry = root / "ml/registry/runtime"
    assets = root / "models/private"
    ocr = json.loads((registry / "small.lock.json").read_text())
    speech = json.loads((registry / "kokoro.lock.json").read_text())
    runtime = json.loads((registry / "ios-runtime.lock.json").read_text())
    model_bundle(assets / "small", ocr)
    model_bundle(assets / speech["bundle_directory"], speech)
    for target in targets:
        pinned_file(assets / "runtime" / target / "libonnxruntime.a", runtime["libraries"][target])
    notices = root / "docs/third-party/licenses"
    for name, expected in json.loads((notices / "manifest.json").read_text()).items():
        if sha(notices / name) != expected:
            raise ValueError(f"Bundled notice hash differs: {name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", choices=[*TARGETS, "all"], default="simulator", nargs="?")
    args = parser.parse_args()
    targets = list(TARGETS.values()) if args.target == "all" else [TARGETS[args.target]]
    verify(ROOT, targets)
    print("Verified native models, runtime and notices without modifying files.")


if __name__ == "__main__":
    main()
