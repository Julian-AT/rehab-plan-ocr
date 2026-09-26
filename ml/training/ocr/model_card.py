"""Register completed OCR experiments from checked training and export evidence.

Both passing and failed parity belong in the registry. Registration never promotes
weights, changes runtime locks or includes private text/pixels in the model card.
"""

import argparse
import json
import math
from collections import Counter
from pathlib import Path

from contract import CRITICAL, sha, validate_dataset
from train import DICTIONARY, ROOT, current_review, lineage, summary


def read(path):
    return json.loads(path.read_text())


def distance(a, b):
    previous = list(range(len(b) + 1))
    for i, left in enumerate(a, 1):
        current = [i]
        for j, right in enumerate(b, 1):
            current.append(min(current[-1] + 1, previous[j] + 1, previous[j - 1] + (left != right)))
        previous = current
    return previous[-1]


def checked_metrics(metrics, samples):
    expected = {r["id"]: r for r in samples if r["partition"] == "validation"}
    rows = metrics["rows"]
    if len(rows) != len(expected) or {r["id"] for r in rows} != set(expected):
        raise ValueError("Validation examples are missing or duplicated")
    for row in rows:
        source = expected[row["id"]]
        if (
            any(row[k] != source[k] for k in ["group", "field", "variant"])
            or row["expected"] != source["text"]
            or not isinstance(row["predicted"], str)
            or row["correct"] is not (row["predicted"] == row["expected"])
            or row["character_errors"] != distance(row["expected"], row["predicted"])
        ):
            raise ValueError("Validation labels, predictions or scores changed")
    for name, chosen in [
        ("overall", rows),
        ("originals", [r for r in rows if r["variant"] == "original"]),
        ("robustness", [r for r in rows if r["variant"] != "original"]),
    ]:
        if metrics[name] != summary(chosen):
            raise ValueError("Validation aggregate does not match retained predictions")
    return {name: metrics[name] for name in ["overall", "originals", "robustness"]}


def describe(run, dataset, root=ROOT):
    root = root.resolve(strict=True)
    run = run.resolve(strict=True)
    if not run.is_relative_to((root / ".local/runs").resolve()):
        raise ValueError("Training evidence must remain in the private run directory")
    config, progress, selection = [
        read(run / f"{name}.json") for name in ["settings", "progress", "selection"]
    ]
    if (
        progress["status"] not in {"validation-stopped", "epoch-limit"}
        or progress["best_epoch"] != selection["epoch"]
        or selection["qualified"] is not False
        or config["mode"] not in {"frozen-backbone", "full"}
        or selection["sha256"] != sha(run / "selected.pdparams")
        or selection["export_config_sha256"] != sha(run / "export.yml")
    ):
        raise ValueError("A completed, unchanged experimental selection is required")
    checkpoint = run / "checkpoints" / f"epoch-{selection['epoch']:04d}"
    receipt = read(checkpoint / "checkpoint.json")
    if (
        receipt["run_identity"] != sha(run / "identity.json")
        or receipt["training_sha256"] != sha(checkpoint / "training.pdstate")
        or receipt["baseline_sha256"] != sha(run / "baseline.json")
        or receipt["metrics"] != selection["metrics"]
        or receipt["epoch"] != selection["epoch"]
    ):
        raise ValueError("Selected checkpoint or baseline evidence changed")
    baseline = read(run / "baseline.json")
    baseline_metrics = checked_metrics(baseline, dataset["samples"])
    selected_metrics = checked_metrics(selection["metrics"], dataset["samples"])
    previous = {r["id"]: r for r in baseline["rows"]}
    new_errors = sorted(
        r["id"]
        for r in selection["metrics"]["rows"]
        if r["field"] in CRITICAL and not r["correct"] and previous[r["id"]]["correct"]
    )
    if sorted(selection["metrics"]["new_critical_errors"]) != new_errors:
        raise ValueError("New critical-error evidence disagrees with retained predictions")
    deployment = run / "deployment"
    export, parity = [read(deployment / f"{name}.json") for name in ["export", "parity"]]
    artifact = deployment / "recognizer.onnx"
    if (
        export["run_identity_sha256"] != sha(run / "identity.json")
        or export["selection_sha256"] != sha(run / "selection.json")
        or export["qualified"] is not False
        or parity["artifact_sha256"] != sha(artifact)
        or parity["checkpoint_sha256"] != selection["sha256"]
        or parity["onnxruntime"] != "1.22.0"
        or parity["provider"] != "CPUExecutionProvider"
        or parity["rtol"] != 1e-3
        or parity["atol"] != 1e-5
        or parity["quality_qualification"] is not False
        or parity["physical_ios_verified"] is not False
    ):
        raise ValueError("Export identity, runtime or parity tolerance changed")
    expected = {(r["id"], w) for r in dataset["samples"] for w in {320, 640, config["width"]}}
    cases = parity["cases"]
    if (
        not cases
        or len(cases) != len(expected)
        or {(r["id"], r["width"]) for r in cases} != expected
        or any(
            type(r["allclose"]) is not bool
            or type(r["same_tokens"]) is not bool
            or (
                r["max_absolute_error"] is not None
                and (
                    type(r["max_absolute_error"]) not in {float, int}
                    or not math.isfinite(r["max_absolute_error"])
                    or r["max_absolute_error"] < 0
                )
            )
            or (r["allclose"] and r["max_absolute_error"] is None)
            for r in cases
        )
    ):
        raise ValueError("Parity cases are incomplete, duplicated or invalid")
    passed = all(r["allclose"] and r["same_tokens"] for r in cases)
    if parity["passed"] is not passed or export["status"] != (
        "desktop-parity-passed" if passed else "interrupted-or-failed"
    ):
        raise ValueError("Export status disagrees with complete parity evidence")
    if passed and export.get("artifact_sha256") != sha(artifact):
        raise ValueError("Successful export artifact changed")
    evidence = [
        run / f"{name}.json"
        for name in ["settings", "identity", "baseline", "progress", "selection"]
    ] + [checkpoint / "checkpoint.json", deployment / "export.json", deployment / "parity.json"]
    return {
        "mode": config["mode"],
        "run": str(run.relative_to(root)),
        "learning_rate": config["learning_rate"],
        "completed_epochs": progress["epoch"],
        "completed_steps": progress["steps"],
        "stop_reason": progress["status"],
        "selected_epoch": selection["epoch"],
        "checkpoint_sha256": selection["sha256"],
        "run_identity_sha256": sha(run / "identity.json"),
        "onnx_sha256": sha(artifact),
        "baseline_metrics": baseline_metrics,
        "selected_metrics": selected_metrics,
        "new_critical_errors": len(new_errors),
        "parity": {
            "passed": passed,
            "cases": len(cases),
            "numeric_cases_passed": sum(r["allclose"] for r in cases),
            "argmax_cases_passed": sum(r["same_tokens"] for r in cases),
            "max_absolute_error": max(
                (r["max_absolute_error"] for r in cases if r["max_absolute_error"] is not None),
                default=None,
            ),
            "rtol": parity["rtol"],
            "atol": parity["atol"],
        },
        "evidence": {str(p.relative_to(run)): sha(p) for p in evidence},
        "qualified": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.parent != ROOT / "ml/registry" or output.suffix != ".json" or output.exists():
        parser.error("Use a new JSON model card directly below ml/registry")
    variants, dataset_identity, settings = [], None, None
    for run in args.run:
        run = run.resolve(strict=True)
        config = read(run / "settings.json")
        path = Path(config["dataset"])
        if read(run / "identity.json") != {
            "settings_sha256": sha(run / "settings.json"),
            "lineage": lineage(path),
        }:
            raise ValueError("Run lineage changed since training")
        dataset = validate_dataset(path, DICTIONARY.read_text().splitlines())
        current_review(dataset, path)
        comparable = {k: v for k, v in config.items() if k not in {"mode", "learning_rate"}}
        if dataset_identity is not None and (
            dataset_identity != sha(path) or settings != comparable
        ):
            raise ValueError("Compared runs must share dataset, seed, width and validation policy")
        dataset_identity, settings = sha(path), comparable
        variants.append(describe(run, dataset))
    if len({v["mode"] for v in variants}) != len(variants):
        raise ValueError("Do not register duplicate adaptation modes in one comparison")
    partitions = {}
    for partition in ["train", "validation"]:
        rows = [r for r in dataset["samples"] if r["partition"] == partition]
        partitions[partition] = {
            "crops": len(rows),
            "source_groups": len({r["group"] for r in rows}),
            "fields": dict(sorted(Counter(r["field"] for r in rows).items())),
        }
    card = {
        "schema_version": 1,
        "model": "PP-OCRv6_small_rec",
        "status": "experimental-crop-adaptation",
        "base_registry": "ocr-base.json",
        "dataset": {"kind": dataset["kind"], "sha256": dataset_identity, "partitions": partitions},
        "variants": variants,
        "registration_source_sha256": sha(Path(__file__)),
        "quality_improvement_established": False,
        "physical_ios_verified": False,
        "promoted": False,
        "limitations": [
            "Crop scores do not measure complete schedules or correction effort.",
            "Source groups do not establish independent real examples for synthetic data.",
            "No human review, physical measurements or runtime promotion is granted.",
        ],
    }
    with output.open("x") as stream:
        json.dump(card, stream, indent=2, allow_nan=False)
        stream.write("\n")
    print(f"Registered {len(variants)} experimental variants; promoted=false: {output}")


if __name__ == "__main__":
    main()
