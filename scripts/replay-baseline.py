#!/usr/bin/env python3
"""Replay an existing frozen baseline with bounded temporary image storage.

Outputs and desktop timings are development evidence; no unconfirmed annotation
is converted to an accuracy result. The frozen executable/configuration are used.
"""
import argparse
import json
import platform
import statistics
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from benchmark import sha, write


def replay(frozen, models, root, destination):
    manifest = json.loads((frozen / "baseline.json").read_text())
    binary = (frozen / "reha").resolve()
    config = (frozen / "config.json").resolve()
    bindings = [(binary, "binary_sha256"), (config, "config_sha256"),
                (models / "manifest.json", "model_manifest_sha256"),
                (root / "inventory.json", "inventory_sha256")]
    for path, key in bindings:
        if sha(path) != manifest[key]:
            raise ValueError(f"Frozen baseline identity changed: {key}")
    inventory = json.loads((root / "inventory.json").read_text())
    destination.mkdir(parents=True, exist_ok=False)
    report = {"kind": "historical_baseline_replay", "created_at": datetime.now(timezone.utc).isoformat(),
              "platform": platform.platform(), "verified_accuracy": False,
              "independent_final_test": False, "physical_iphone_measurement": False,
              "baseline_created_at": manifest["created_at"], "binary_sha256": manifest["binary_sha256"],
              "config_sha256": manifest["config_sha256"], "model_manifest_sha256": manifest["model_manifest_sha256"],
              "inventory_sha256": manifest["inventory_sha256"], "results": []}
    seen = set()
    for entry in inventory["entries"]:
        digest = entry["sha256"]
        if digest in seen:
            continue
        seen.add(digest)
        source = (root / "raw" / entry["filename"]).resolve()
        if not source.is_relative_to((root / "raw").resolve()) or sha(source) != digest:
            raise ValueError("Original checksum or path mismatch.")
        for path, key in bindings:
            if sha(path) != manifest[key]:
                raise ValueError(f"Frozen baseline changed during replay: {key}")
        with tempfile.TemporaryDirectory(prefix="reha-baseline-replay-") as temporary:
            output = Path(temporary)
            with (destination / f"{digest}.log").open("w") as log:
                try:
                    process = subprocess.run([str(binary), "scan", str(source), str(output), str(models.resolve()), str(config)],
                                             stdout=log, stderr=log, timeout=75, check=False)
                    status = "completed" if process.returncode == 0 else "failed"
                except subprocess.TimeoutExpired:
                    status = "timeout"
            run_path = output / "run.json"
            run = json.loads(run_path.read_text()) if run_path.exists() else {}
            if run:
                write(destination / f"{digest}.json", run)
            report["results"].append({"source_hash": digest, "status": status, "total_ms": run.get("total_ms"),
                                      "run_sha256": sha(run_path) if run_path.exists() else None})
            times = [r["total_ms"] for r in report["results"] if isinstance(r["total_ms"], (int, float))]
            report["timing_ms"] = {"count": len(times), "median": statistics.median(times) if times else None,
                                   "minimum": min(times, default=None), "maximum": max(times, default=None)}
            write(destination / "summary.json", report)
        print(f"Replay {len(report['results'])}: {status}", flush=True)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for argument in ["frozen", "models", "root", "destination"]:
        parser.add_argument("--" + argument, type=Path, required=True)
    args = parser.parse_args()
    report = replay(args.frozen, args.models, args.root, args.destination)
    print(json.dumps(report["timing_ms"]))
    if any(row["status"] != "completed" for row in report["results"]):
        raise SystemExit("Replay enthält fehlgeschlagene Durchläufe.")


if __name__ == "__main__":
    main()
