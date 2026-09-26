# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml==6.0.3"]
# ///
"""Download public model weights only. Never reads or uploads document data."""

import argparse
import hashlib
import json
import urllib.request
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]


def fetch(url):
    with urllib.request.urlopen(url, timeout=120) as response:
        return response.read()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tier", choices=["small", "tiny", "medium"], default="small")
    args = parser.parse_args()
    destination = ROOT / "models/private" / args.tier
    destination.mkdir(parents=True, exist_ok=True)
    manifest_path = ROOT / "models" / f"{args.tier}.lock.json"
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
        path = destination / entry["path"]
        if (
            path.exists()
            and entry.get("sha256") == hashlib.sha256(path.read_bytes()).hexdigest()
        ):
            print(f"Verified {entry['path']}")
            continue
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
    (destination / "dictionary.json").write_text(
        json.dumps(dictionary, ensure_ascii=False)
    )
    manifest["dictionary_sha256"] = hashlib.sha256(
        (destination / "dictionary.json").read_bytes()
    ).hexdigest()
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    (destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Ready: {destination}")


if __name__ == "__main__":
    main()
