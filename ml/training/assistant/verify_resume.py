"""Prove exact adapter, optimizer, random-state and validation parity after resume."""

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from ml.training.assistant.contract import sha, write  # noqa: E402
from ml.training.assistant.train import (  # noqa: E402
    current_identity,
    latest_checkpoint,
    restore_random,
)


def compare(resumed, continuous, destination):
    import mlx.core as mx

    left_settings, _ = current_identity(resumed)
    right_settings, _ = current_identity(continuous)
    if left_settings != right_settings:
        raise ValueError("Resume comparison requires identical settings")
    left, a = latest_checkpoint(resumed)
    right, b = latest_checkpoint(continuous)
    if not left or not right or a["state"] != b["state"]:
        raise ValueError("Training state differs")
    mismatches, count = [], 0
    for name in ["adapters.safetensors", "optimizer.safetensors", "random.safetensors"]:
        x, y = mx.load(str(left / name)), mx.load(str(right / name))
        if set(x) != set(y):
            mismatches.append(name + ": keys")
            continue
        for key in x:
            count += 1
            if (
                x[key].dtype != y[key].dtype
                or x[key].shape != y[key].shape
                or not mx.array_equal(x[key], y[key]).item()
            ):
                mismatches.append(name + ": " + key)
    rng = mx.load(str(left / "random.safetensors"))
    restore_random(rng)
    expected = mx.random.normal((32,)).tolist()
    restore_random(rng)
    random_round_trip = expected == mx.random.normal((32,)).tolist()
    same_validation = json.loads((left / "metrics.json").read_text()) == json.loads(
        (right / "metrics.json").read_text()
    )
    report = {
        "schema_version": 1,
        "kind": "complete-epoch-resume-parity",
        "qualified": False,
        "exact": not mismatches and same_validation and random_round_trip,
        "compared_tensors": count,
        "mismatches": mismatches,
        "validation_equal": same_validation,
        "random_round_trip": random_round_trip,
        "epoch": a["epoch"],
        "steps": a["state"]["steps"],
        "run_identity_sha256": [sha(run / "identity.json") for run in [resumed, continuous]],
    }
    write(destination, report)
    print(json.dumps(report, indent=2))
    if not report["exact"]:
        raise ValueError("Resume parity failed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resumed", type=Path, required=True)
    parser.add_argument("--continuous", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    compare(args.resumed.resolve(), args.continuous.resolve(), args.report.resolve())


if __name__ == "__main__":
    main()
