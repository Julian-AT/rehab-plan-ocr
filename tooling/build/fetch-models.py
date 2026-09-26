# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml==6.0.3"]
# ///
"""Download public model weights only. Never reads or uploads document data."""

import argparse
import hashlib
import json
import os
import stat
import tempfile
import urllib.request
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]


def fetch(url):
    with urllib.request.urlopen(url, timeout=120) as response:
        return response.read()


def write_if_changed(path, content):
    """Preserve verified build inputs; publish regenerated metadata atomically."""
    if path.is_file() and path.read_bytes() == content:
        return
    descriptor, name = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}-")
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            os.fchmod(
                stream.fileno(), stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
            )
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tier", choices=["small", "tiny", "medium"], default="small")
    parser.add_argument(
        "--update-lock", action="store_true", help="Explicitly create/update model pins"
    )
    parser.add_argument(
        "--offline", action="store_true", help="Verify local assets without downloading"
    )
    args = parser.parse_args()
    destination = ROOT / ".local/models/runtime" / args.tier
    destination.mkdir(parents=True, exist_ok=True)
    manifest_path = ROOT / "ml/registry/runtime" / f"{args.tier}.lock.json"
    if not manifest_path.exists() and not args.update_lock:
        raise SystemExit("Model lock missing; use --update-lock explicitly to select a model.")
    manifest = (
        json.loads(manifest_path.read_text())
        if manifest_path.exists()
        else {
            "schema_version": 1,
            "engine": f"PP-OCRv6_{args.tier}",
            "runtime": "ONNX Runtime 1.22.0 / ort 2.0.0-rc.10",
            "license": "Apache-2.0",
            "files": [],
        }
    )
    if not manifest["files"]:
        if not args.update_lock or args.offline:
            raise SystemExit("Model lock has no pinned files.")
        for component in ["det", "rec"]:
            repo = f"PaddlePaddle/PP-OCRv6_{args.tier}_{component}_onnx"
            metadata = json.loads(fetch(f"https://huggingface.co/api/models/{repo}"))
            for filename in ["inference.onnx", "inference.yml"]:
                manifest["files"].append(
                    {
                        "path": f"{component}-{filename}",
                        "url": f"https://huggingface.co/{repo}/resolve/{metadata['sha']}/{filename}",
                    }
                )
    for entry in manifest["files"]:
        if not args.update_lock and not entry.get("sha256"):
            raise SystemExit(f"Missing pinned checksum: {entry['path']}")
        path = destination / entry["path"]
        if path.exists() and entry.get("sha256") == hashlib.sha256(path.read_bytes()).hexdigest():
            print(f"Verified {entry['path']}")
            continue
        if args.offline:
            raise SystemExit(f"Missing or corrupt local model: {entry['path']}; run make restore.")
        content = fetch(entry["url"])
        digest = hashlib.sha256(content).hexdigest()
        if entry.get("sha256") and digest != entry["sha256"]:
            raise SystemExit(f"Checksum mismatch: {entry['path']}")
        entry.update(sha256=digest, bytes=len(content))
        temporary = path.with_suffix(path.suffix + ".part")
        temporary.write_bytes(content)
        temporary.replace(path)
        print(f"Downloaded {entry['path']}: {len(content)} bytes")
    config = yaml.safe_load((destination / "rec-inference.yml").read_text())
    characters = config["PostProcess"]["character_dict"]
    # Paddle CTC: blank token first, space appended by CTCLabelDecode.
    dictionary = [""] + characters + [" "]
    dictionary_bytes = json.dumps(dictionary, ensure_ascii=False).encode("utf-8")
    digest = hashlib.sha256(dictionary_bytes).hexdigest()
    if not args.update_lock and manifest.get("dictionary_sha256") != digest:
        raise SystemExit("Dictionary differs from the pinned deployment dictionary.")
    write_if_changed(destination / "dictionary.json", dictionary_bytes)
    if args.update_lock:
        manifest["dictionary_sha256"] = digest
        write_if_changed(manifest_path, (json.dumps(manifest, indent=2) + "\n").encode())
    write_if_changed(
        destination / "manifest.json", (json.dumps(manifest, indent=2) + "\n").encode()
    )
    print(f"Ready: {destination}")


if __name__ == "__main__":
    main()
