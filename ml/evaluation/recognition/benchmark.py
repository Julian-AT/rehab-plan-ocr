"""Evaluate explicitly approved original photos, preserving four development folds.

Variants and synthetic plans never inflate original-photo accuracy. This dataset
has already been inspected and cannot support an independent final quality claim.
"""

import argparse
import hashlib
import json
import platform
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tooling/dev"))
import workspace  # noqa: E402

PRIVATE = ROOT / ".local/datasets/private"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def freeze_baseline(binary, models, config, root, destination):
    """Freeze the portable implementation without granting label approval.

    This can precede annotation. Timings/outputs are development evidence only;
    an accuracy benchmark still goes through the existing approved preflight.
    """
    destination.mkdir(parents=True, exist_ok=False)
    shutil.copy2(binary, destination / "reha")
    shutil.copy2(config, destination / "config.json")
    shutil.copy2(models / "manifest.json", destination / "model-manifest.json")
    source_files = [
        ROOT / "packages/rust/reha-core/src" / (name + ".rs")
        for name in [
            "parser",
            "pipeline",
            "ocr",
            "review",
            "refinement",
            "geometry",
            "photo",
            "photo_macos",
            "contracts",
        ]
    ]
    manifest = {
        "schema_version": 1,
        "kind": "unchanged_portable_baseline",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "verified_accuracy": False,
        "independent_final_test": False,
        "binary_sha256": sha(destination / "reha"),
        "config_sha256": sha(destination / "config.json"),
        "model_manifest_sha256": sha(destination / "model-manifest.json"),
        "portable_sources": {str(p.relative_to(ROOT)): sha(p) for p in source_files},
        "inventory_sha256": sha(root / "inventory.json"),
        "acceptance_targets": {
            "critical_field_correctness": 0.99,
            "appointment_precision": 0.99,
            "appointment_recall": 0.99,
            "whole_plan_correctness": 0.90,
            "observed_critical_false_acceptance": 0,
        },
    }
    write(destination / "baseline.json", manifest)
    return manifest


def record_baseline_runs(binary, models, root, destination):
    """Record unchanged outputs and latency, never accuracy on unapproved labels."""
    manifest = json.loads((destination / "baseline.json").read_text())
    binary = (destination / "reha").resolve()
    for path, key in [
        (binary, "binary_sha256"),
        (destination / "config.json", "config_sha256"),
        (models / "manifest.json", "model_manifest_sha256"),
        (root / "inventory.json", "inventory_sha256"),
    ]:
        if sha(path) != manifest[key]:
            raise ValueError(f"Frozen baseline identity changed: {key}")
    inventory = json.loads((root / "inventory.json").read_text())
    results = []
    seen = set()
    for entry in inventory["entries"]:
        source_hash = entry["sha256"]
        if source_hash in seen:
            continue
        seen.add(source_hash)
        source = root / "raw" / entry["filename"]
        if sha(source) != source_hash:
            raise ValueError("Original checksum mismatch.")
        output = destination / "runs" / source_hash
        output.mkdir(parents=True)
        with (output / "process.log").open("w") as log:
            try:
                result = subprocess.run(
                    [
                        str(binary),
                        "scan",
                        str(source.resolve()),
                        str(output.resolve()),
                        str(models.resolve()),
                        str((destination / "config.json").resolve()),
                    ],
                    stdout=log,
                    stderr=log,
                    timeout=75,
                )
                status = "completed" if result.returncode == 0 else "failed"
            except subprocess.TimeoutExpired:
                status = "timeout"
        run_path = output / "run.json"
        run = json.loads(run_path.read_text()) if run_path.exists() else {}
        results.append(
            {
                "source_hash": source_hash,
                "status": status,
                "total_ms": run.get("total_ms"),
                "run_sha256": sha(run_path) if run_path.exists() else None,
            }
        )
        write(
            destination / "timings.json",
            {"verified_accuracy": False, "physical_iphone_measurement": False, "results": results},
        )


def preflight(root, binary):
    split = json.loads((root / "split.json").read_text())
    if split.get("grouping_verified") is not True:
        raise ValueError("Verify page/capture relationships before comparing grouped references.")
    if split.get("schema_version") != 3 or split.get("final_holdout_available") is not False:
        raise ValueError("Four frozen development folds (schema 3) required.")
    refs = {}
    for group in split["days"].values():
        for h in group["document_hashes"]:
            path = root / "labels/provisional" / f"{h}.json"
            ref = json.loads(path.read_text())
            if not ref.get("verified") or not ref.get("reviewed_at") or ref["uncertainty_notes"]:
                raise ValueError("Every selected original reference must be explicitly approved.")
            result = subprocess.run(
                [str(binary), "reference-check", str(path), "--approved"],
                check=True,
                capture_output=True,
                text=True,
            )
            if result.stdout.strip() != ref.get("approval_hash"):
                raise ValueError("Reference changed after approval.")
            refs[h] = path
    # The native grouping implementation also checks relationship changes.
    result = subprocess.run(
        [str(binary), "reference-groups", str(root)],
        check=True,
        capture_output=True,
        text=True,
    )
    if json.loads(result.stdout) != split:
        raise ValueError("Frozen source relationships changed.")
    return split, refs


def summarize(results):
    keys = [
        "reference_count",
        "predicted_count",
        "matched_count",
        "fully_correct_count",
        "missed_count",
        "invented_count",
        "date_correct",
        "start_correct",
        "end_or_duration_correct",
        "location_correct",
        "therapist_correct",
        "notes_correct",
        "unresolved_count",
        "character_errors",
        "reference_characters",
        "row_assignment_errors",
        "column_assignment_errors",
        "incorrect_unflagged_fields",
        "automatically_correct_count",
        "field_corrections_needed",
        "critical_printed_fields",
        "correct_critical_printed_fields",
    ]
    counts = {key: sum(r["metrics"][key] for r in results) for key in keys}
    for key in [
        "printed_fields",
        "correct_printed_fields",
        "empty_fields",
        "correct_empty_fields",
    ]:
        counts[key] = {
            f: sum(r["metrics"][key].get(f, 0) for r in results)
            for f in ["date", "start", "end", "title", "location", "therapist", "notes"]
        }
    return {
        "photos": len(results),
        "plan_photos": sum(
            r.get("input_class", "rehabilitation_plan") == "rehabilitation_plan" for r in results
        ),
        "negative_or_unusable_photos": sum(
            r.get("input_class", "rehabilitation_plan") != "rehabilitation_plan" for r in results
        ),
        "negative_inputs_with_invented_appointments": sum(
            r.get("input_class") == "non_plan" and r["metrics"]["invented_count"] > 0
            for r in results
        ),
        "counts": counts,
        "critical_field_accuracy": counts["correct_critical_printed_fields"]
        / counts["critical_printed_fields"]
        if counts["critical_printed_fields"]
        else None,
        "whole_plan_correctness": {
            "numerator": sum(
                r["metrics"]["schedule_without_correction"]
                for r in results
                if r.get("input_class", "rehabilitation_plan") == "rehabilitation_plan"
            ),
            "denominator": sum(
                r.get("input_class", "rehabilitation_plan") == "rehabilitation_plan"
                for r in results
            ),
        },
        "appointment_precision": counts["matched_count"] / counts["predicted_count"]
        if counts["predicted_count"]
        else None,
        "appointment_recall": counts["matched_count"] / counts["reference_count"]
        if counts["reference_count"]
        else None,
        "review_burden": {
            "unresolved_appointments": counts["unresolved_count"],
            "predicted_appointments": counts["predicted_count"],
            "field_corrections_needed": counts["field_corrections_needed"],
        },
        "fully_correct_photos": sum(r["metrics"]["schedule_without_correction"] for r in results),
        "maximum_ms": max((r["total_ms"] for r in results), default=0),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--models", required=True, type=Path)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument(
        "--binary", type=Path, default=workspace.cargo_directory(ROOT) / "release/reha"
    )
    parser.add_argument(
        "--evaluator",
        type=Path,
        help="Separate evaluator for newer annotation contracts; extraction binary remains frozen",
    )
    parser.add_argument("--root", type=Path)
    parser.add_argument("--fold", type=int, choices=range(4))
    parser.add_argument("--final", action="store_true")
    parser.add_argument(
        "--freeze-baseline",
        type=Path,
        help="New private directory; freeze binaries/config before accuracy work, without approving labels",
    )
    parser.add_argument("--record-baseline-runs", action="store_true")
    args = parser.parse_args()
    root = args.root or PRIVATE
    if args.freeze_baseline:
        if args.final:
            raise ValueError("Freezing a baseline is not final acceptance.")
        freeze_baseline(args.binary.resolve(), args.models, args.config, root, args.freeze_baseline)
        if args.record_baseline_runs:
            record_baseline_runs(
                (args.freeze_baseline / "reha").resolve(), args.models, root, args.freeze_baseline
            )
        print(args.freeze_baseline)
        return
    if args.final:
        raise ValueError(
            "Previously inspected originals are not an independent final test. Obtain new plans."
        )
    evaluator = (args.evaluator or args.binary).resolve()
    split, refs = preflight(root, evaluator)
    inventory = {
        e["sha256"]: e for e in json.loads((root / "inventory.json").read_text())["entries"]
    }
    output = (
        ROOT
        / ".local/runs/recognition"
        / f"benchmark-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')}"
    )
    output.mkdir(parents=True, exist_ok=False)
    manifest = {
        "schema_version": 2,
        "kind": "grouped_development_originals",
        "independent_final_test": False,
        "platform": platform.platform(),
        "config_sha256": sha(args.config),
        "model_manifest_sha256": sha(args.models / "manifest.json"),
        "binary_sha256": sha(args.binary),
        "evaluator_sha256": sha(evaluator),
        "split_sha256": sha(root / "split.json"),
        "reference_hashes": {
            h: json.loads(p.read_text())["approval_hash"] for h, p in refs.items()
        },
        "results": [],
    }
    write(output / "manifest.json", manifest)
    for group_id, group in split["days"].items():
        if args.fold is not None and group["fold"] != args.fold:
            continue
        for h in group["document_hashes"]:
            if (
                sha(args.config) != manifest["config_sha256"]
                or sha(args.models / "manifest.json") != manifest["model_manifest_sha256"]
                or json.loads(refs[h].read_text()).get("approval_hash")
                != manifest["reference_hashes"][h]
            ):
                raise ValueError(
                    "Configuration, model or approved reference changed during the benchmark."
                )
            photo = root / "raw" / inventory[h]["filename"]
            if sha(photo) != h:
                raise ValueError("Original checksum mismatch.")
            destination = output / group_id / h
            subprocess.run(
                [
                    str(args.binary.resolve()),
                    "scan",
                    str(photo),
                    str(destination),
                    str(args.models.resolve()),
                    str(args.config.resolve()),
                ],
                check=True,
            )
            subprocess.run(
                [
                    str(evaluator),
                    "evaluate",
                    str(refs[h]),
                    str(destination / "run.json"),
                    str(destination / "metrics.json"),
                ],
                check=True,
                capture_output=True,
            )
            run = json.loads((destination / "run.json").read_text())
            manifest["results"].append(
                {
                    "group": group_id,
                    "fold": group["fold"],
                    "source_hash": h,
                    "input_class": json.loads(refs[h].read_text()).get(
                        "input_class", "rehabilitation_plan"
                    ),
                    "run_sha256": sha(destination / "run.json"),
                    "total_ms": run["total_ms"],
                    "metrics": json.loads((destination / "metrics.json").read_text()),
                }
            )
            write(output / "manifest.json", manifest)
    results = manifest["results"]
    report = {
        "scope": "Previously explored development originals; correlated captures remain grouped.",
        "overall": summarize(results),
        "folds": {str(f): summarize([r for r in results if r["fold"] == f]) for f in range(4)},
        "groups": {
            g: summarize([r for r in results if r["group"] == g])
            for g in {r["group"] for r in results}
        },
        "verified_accuracy": True,
        "independent_final_test": False,
    }
    write(output / "report.json", report)
    print(output)


if __name__ == "__main__":
    main()
