"""Bounded offline comparison of the portable draft and two optional crop readers.

This reports source-linked proposals and resource use, never accuracy from
unverified references. No output can approve a field or write calendar events.
"""

import argparse
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tooling/dev"))
import workspace  # noqa: E402


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def compare(run_path, output, manifest_path, candidate_id=None, cancel_file=None):
    output.mkdir(parents=True, exist_ok=False)
    run = json.loads(run_path.read_text())
    subprocess.run(
        [
            str(workspace.cargo_directory(ROOT) / "release/reha"),
            "experiment-crop",
            str(run_path),
            str(output),
        ],
        check=True,
    )
    crop = json.loads((output / "crop.json").read_text())
    manifest = json.loads(manifest_path.read_text())
    if sha(manifest["binary"]) != manifest["binary_sha256"]:
        raise ValueError("Adapter binary changed; repeat compatibility checks.")
    if manifest["lock_sha256"] != sha(ROOT / "ml/registry/runtime/vlm-experiments.lock.json"):
        raise ValueError("Experiment lock changed; repeat compatibility checks.")
    result = {
        "manifest_sha256": sha(manifest_path),
        "adapter_sha256": manifest["binary_sha256"],
        "runtime_revision": manifest["runtime_revision"],
        "run_sha256": sha(run_path),
        "crop_tool_sha256": sha(workspace.cargo_directory(ROOT) / "release/reha"),
        "runner_sha256": sha(Path(__file__)),
        "platform": __import__("platform").platform(),
        "schema_version": 1,
        "source": crop,
        "portable": {
            "engine": run["engine"],
            "total_ms": run["total_ms"],
            "appointments": len(run["appointments"]),
        },
        "readers": [],
        "verified_accuracy": None,
        "packaging_eligible": False,
        "reason": "Verified grouped references and physical-device qualification required.",
    }
    for candidate in manifest["candidates"]:
        if candidate_id and candidate["id"] != candidate_id:
            continue
        if cancel_file and cancel_file.exists():
            break
        item = {"candidate": candidate["id"], "status": "unavailable", "approved": False}
        try:
            if not candidate.get("compatible"):
                raise ValueError("Checkpoint has not passed the image compatibility test.")
            for field in ["model", "projector"]:
                if sha(candidate[field]) != candidate[field + "_sha256"]:
                    raise ValueError("Checkpoint checksum changed.")
            destination = output / (candidate["id"] + ".json")
            command = [
                manifest["binary"],
                candidate["model"],
                candidate["projector"],
                candidate["id"],
                str(output / "crop.png"),
                str(destination),
            ]
            if __import__("platform").system() == "Darwin":
                command = [
                    "/usr/bin/sandbox-exec",
                    "-p",
                    "(version 1) (allow default) (deny network*)",
                    *command,
                ]
            with (output / (candidate["id"] + ".log")).open("w") as log:
                process = subprocess.Popen(command, stdout=log, stderr=log)
                started = time.monotonic()
                while process.poll() is None:
                    if time.monotonic() - started >= 60 or (cancel_file and cancel_file.exists()):
                        process.kill()
                        process.wait()
                        raise ValueError(
                            "Stopped at deadline or user cancellation; portable draft retained."
                        )
                    time.sleep(0.05)
                if process.returncode:
                    raise ValueError("Local reader failed; see retained log.")
            item.update(json.loads(destination.read_text()))
            item["checkpoint"] = candidate
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            item["reason"] = str(error)
        result["readers"].append(item)
    (output / "comparison.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    return result


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("run", type=Path)
    p.add_argument("output", type=Path)
    p.add_argument(
        "--manifest", type=Path, default=ROOT / ".local/models/runtime/experiments/candidates.json"
    )
    p.add_argument("--candidate", choices=["glm-ocr", "paddleocr-vl-1.6"])
    p.add_argument("--cancel-file", type=Path)
    a = p.parse_args()
    r = compare(a.run, a.output, a.manifest, a.candidate, a.cancel_file)
    print(
        json.dumps(
            {
                "readers": [
                    {"candidate": v["candidate"], "status": v["status"]} for v in r["readers"]
                ],
                "packaging_eligible": False,
            }
        )
    )
