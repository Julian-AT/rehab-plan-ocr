"""Compare all tensors after uninterrupted and resumed synthetic training."""

import argparse
import json
from pathlib import Path

import numpy as np
import paddle
from contract import sha, write
from train import WEIGHTS, latest_checkpoint


def compare(left, right, prefix=""):
    mismatches, tensors = [], 0
    if isinstance(left, (paddle.Tensor, np.ndarray)):
        tensors = 1
        a = left.numpy() if isinstance(left, paddle.Tensor) else left
        b = right.numpy() if isinstance(right, paddle.Tensor) else right
        if not isinstance(b, np.ndarray) or a.dtype != b.dtype or not np.array_equal(a, b):
            mismatches.append(prefix)
    elif isinstance(left, dict):
        if not isinstance(right, dict) or set(left) != set(right):
            return [prefix + "/keys"], 0
        for key in left:
            bad, count = compare(left[key], right[key], prefix + "/" + str(key))
            mismatches.extend(bad)
            tensors += count
    elif isinstance(left, (list, tuple)):
        if not isinstance(right, type(left)) or len(left) != len(right):
            return [prefix + "/length"], 0
        for index, (a, b) in enumerate(zip(left, right, strict=True)):
            bad, count = compare(a, b, prefix + "/" + str(index))
            mismatches.extend(bad)
            tensors += count
    elif left != right:
        mismatches.append(prefix)
    return mismatches, tensors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resumed", type=Path, required=True)
    parser.add_argument("--continuous", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    settings = [
        json.loads((run / "settings.json").read_text()) for run in [args.resumed, args.continuous]
    ]
    if settings[0] != settings[1]:
        raise ValueError("Resume comparison needs identical recorded training settings")
    paths, receipts = zip(
        *(latest_checkpoint(run) for run in [args.resumed, args.continuous]), strict=True
    )
    if any(path is None for path in paths) or receipts[0]["state"] != receipts[1]["state"]:
        raise ValueError("Completed training state differs")
    checkpoints = [paddle.load(str(path / "training.pdstate")) for path in paths]
    mismatches, tensors = compare(*checkpoints)
    original = paddle.load(str(WEIGHTS))
    backbone = {k: v for k, v in checkpoints[0]["model"].items() if k.startswith("backbone.")}
    backbone_mismatches, backbone_tensors = compare({k: original[k] for k in backbone}, backbone)
    frozen = settings[0]["mode"] == "frozen-backbone"
    report = {
        "kind": "epoch-boundary-resume-parity",
        "exact": not mismatches,
        "compared_tensors": tensors,
        "mismatches": mismatches,
        "backbone_tensors": backbone_tensors,
        "backbone_unchanged": not backbone_mismatches,
        "backbone_mismatches": backbone_mismatches,
        "epoch": receipts[0]["epoch"],
        "steps": receipts[0]["state"]["steps"],
        "mode": settings[0]["mode"],
        "run_identity_sha256": [
            sha(run / "identity.json") for run in [args.resumed, args.continuous]
        ],
        "qualified": False,
    }
    write(args.report, report)
    print(
        json.dumps(
            {
                k: report[k]
                for k in ["exact", "compared_tensors", "backbone_unchanged", "epoch", "steps"]
            }
        )
    )
    if mismatches or (frozen and backbone_mismatches):
        raise SystemExit("Resume/freeze parity failed")


if __name__ == "__main__":
    main()
