"""Fetch pinned development-only checkpoints. Never downloads document content.

PaddleOCR-VL-1.6 is converted locally using the pinned runtime converter. Files
without upstream SHA256 are hashed into the private conversion manifest after
fetching from their immutable revision. No downloaded Python model code is run.
"""

import argparse
import hashlib
import json
import re
from pathlib import Path

import vlm_process

ROOT = Path(__file__).resolve().parents[3]


def verify_candidate(directory, candidate):
    """Reuse bytes only against the original download receipt or an upstream hash."""
    try:
        manifest = directory / "source-manifest.json"
        recorded = (
            json.loads(manifest.read_text()) if manifest.exists() or manifest.is_symlink() else None
        )
        expected_files = {item["path"]: item for item in candidate["files"]}
        if len(expected_files) != len(candidate["files"]) or any(
            Path(name).name != name for name in expected_files
        ):
            raise ValueError("Unsafe or duplicate checkpoint path")
        if recorded is None and any(not item["sha256"] for item in expected_files.values()):
            raise ValueError("Original download receipt is required for unhashed upstream files")
        records = {}
        if recorded is not None:
            if any(recorded[key] != candidate[key] for key in ["id", "repository", "revision"]):
                raise ValueError("Download origin changed")
            records = {item["path"]: item for item in recorded["files"]}
            if set(records) != set(expected_files) or len(records) != len(recorded["files"]):
                raise ValueError("Download receipt files are missing or duplicated")
        verified = []
        for name, item in expected_files.items():
            path = directory / name
            expected = item["sha256"]
            if recorded is not None:
                previous = records[name]
                if (
                    previous["bytes"] != item["bytes"]
                    or not isinstance(previous["sha256"], str)
                    or not re.fullmatch(r"[0-9a-f]{64}", previous["sha256"])
                    or (expected and previous["sha256"] != expected)
                ):
                    raise ValueError("Download receipt identity is invalid")
                expected = previous["sha256"]
            if path.stat().st_size != item["bytes"]:
                raise ValueError("Checkpoint size changed")
            with path.open("rb") as source:
                actual = hashlib.file_digest(source, "sha256").hexdigest()
            if actual != expected:
                raise ValueError("Checkpoint differs from its original identity")
            verified.append({**item, "sha256": actual})
        return verified
    except (OSError, KeyError, TypeError, ValueError) as error:
        raise ValueError(
            "Checkpoint provenance is missing or changed; preserve this directory and "
            "explicitly download to a new --destination for a new receipt"
        ) from error


def fetch(lock, destination, *, phase_timeout=vlm_process.PHASE_SECONDS):
    vlm_process.deadline(phase_timeout)
    for candidate in lock["candidates"]:
        if Path(candidate["id"]).name != candidate["id"]:
            raise ValueError("Unsafe candidate directory")
        directory = destination / candidate["id"]
        if directory.exists() or directory.is_symlink():
            verify_candidate(directory, candidate)
            continue  # Never rewrite or regenerate an existing provenance receipt.
        directory.mkdir(parents=True, exist_ok=False)
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
                vlm_process.run(
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
                    timeout=phase_timeout,
                )
                if not valid(partial):
                    raise ValueError(f"Checkpoint integrity failed: {name}")
                partial.replace(target)
            with target.open("rb") as source:
                checksum = hashlib.file_digest(source, "sha256").hexdigest()
            verified.append({"path": name, "sha256": checksum, "bytes": target.stat().st_size})
        with (directory / "source-manifest.json").open("x") as manifest:
            manifest.write(json.dumps({**candidate, "files": verified}, indent=2) + "\n")


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--destination", type=Path, default=ROOT / ".local/models/runtime/experiments/checkpoints"
    )
    p.add_argument("--phase-timeout-seconds", type=float, default=vlm_process.PHASE_SECONDS)
    a = p.parse_args()
    fetch(
        json.loads((ROOT / "ml/registry/runtime/vlm-experiments.lock.json").read_text()),
        a.destination,
        phase_timeout=a.phase_timeout_seconds,
    )
