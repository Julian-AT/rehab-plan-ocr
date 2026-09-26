#!/usr/bin/env python3
"""Restore pinned speech sources separately from explicit offline conversion."""

import argparse
import hashlib
import json
import shutil
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def valid(path, entry):
    return (
        path.is_file()
        and digest(path) == entry["sha256"]
        and ("bytes" not in entry or path.stat().st_size == entry["bytes"])
    )


def restore(path, entry):
    if valid(path, entry):
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".download")
    subprocess.run(
        [
            "curl",
            "--fail",
            "--location",
            "--silent",
            "--show-error",
            "--retry",
            "3",
            "--retry-all-errors",
            "--max-time",
            "600",
            entry["url"],
            "--output",
            str(temporary),
        ],
        check=True,
    )
    if not valid(temporary, entry):
        raise RuntimeError(f"Speech source checksum mismatch: {path.name}")
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["restore", "convert"], default="restore", nargs="?")
    args = parser.parse_args()
    registry = ROOT / "ml/registry/runtime"
    manifest = json.loads((registry / "kokoro.lock.json").read_text())
    target = ROOT / ".local/models/runtime" / manifest["bundle_directory"]
    entries = {entry["path"]: entry for entry in manifest["files"]}
    if args.mode == "restore":
        sources = json.loads((registry / "victoria-source.lock.json").read_text())
        for name, entry in sources["files"].items():
            restore(ROOT / ".local/models/runtime/kikiri-victoria-source" / name, entry)
        for name, entry in entries.items():
            if "remote" not in entry and "remote_url" not in entry:
                continue
            url = (
                entry.get("remote_url")
                or f"https://huggingface.co/{manifest['model']}/resolve/{manifest['revision']}/{entry['remote']}"
            )
            restore(target / name, entry | {"url": url})
        print("Verified speech sources and metadata; conversion remains explicit.")
        return

    for name, entry in entries.items():
        if ("remote" in entry or "remote_url" in entry) and not valid(target / name, entry):
            raise RuntimeError(f"Missing speech metadata {name}; run make restore.")
    if not all(valid(target / name, entries[name]) for name in ["model.onnx", "voice.f32"]):
        subprocess.run(
            ["uv", "run", "--offline", "--locked", str(ROOT / "tooling/build/export-victoria.py")],
            check=True,
        )
    expected_vocab = json.loads((registry / "kokoro-vocab.json").read_text())
    if json.loads((target / "config.json").read_text())["vocab"] != expected_vocab:
        raise RuntimeError("Speech vocabulary differs from the deployment dictionary")
    raw = (target / "voice.f32").read_bytes()
    if len(raw) != 510 * 256 * 4 or not all(
        abs(value[0]) < float("inf") for value in struct.iter_unpack("<f", raw)
    ):
        raise RuntimeError("Invalid Victoria voice shape or values")
    for source, name in [
        ("ml/registry/runtime/kokoro-vocab.json", "vocab.json"),
        ("docs/third-party/licenses/kokoro-apache-2.0.txt", "LICENSE"),
        ("docs/third-party/licenses/kokoro-source.txt", "NOTICE"),
    ]:
        shutil.copyfile(ROOT / source, target / name)
    data = ROOT / ".local/builds/phonemizer/host/espeak-ng-data"
    if not (data / "de_dict").is_file():
        raise RuntimeError("Phonemizer data missing; run make convert.")
    for name in entries:
        if name.startswith("espeak-ng-data/"):
            destination = target / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(data / name.removeprefix("espeak-ng-data/"), destination)
    for name, entry in entries.items():
        if not valid(target / name, entry):
            raise RuntimeError(f"Bundled speech asset checksum mismatch: {name}")
    shutil.copyfile(registry / "kokoro.lock.json", target / "manifest.json")
    print(f"Verified {len(entries)} bundled speech assets (24 kHz); no network used.")


if __name__ == "__main__":
    main()
