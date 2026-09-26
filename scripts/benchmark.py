"""Run locally verified development days with pinned models and raw-count reports.

No model is selected automatically, no training is performed, and no hosted AI is used.
Final holdout execution requires --final with a frozen selection file; the one-shot
marker is written before inference so interrupted runs cannot silently be repeated.
"""

import argparse
import hashlib
import json
import os
import platform
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / "data/private"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--models", required=True, type=Path)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--binary", type=Path, default=ROOT / "target/release/reha")
    parser.add_argument("--final", action="store_true")
    parser.add_argument(
        "--selection",
        type=Path,
        help="Frozen selection JSON with config_sha256 and model_manifest_sha256",
    )
    args = parser.parse_args()
    split_path = PRIVATE / "split.json"
    split = json.loads(split_path.read_text())
    if split.get("grouping_verified") is False:
        raise ValueError("Verify page/capture relationships before comparing grouped references.")
    if split.get("schema_version") != 2:
        raise ValueError(
            "Use a frozen split with explicit complete captures and page identities (schema 2)."
        )
    inventory = json.loads((PRIVATE / "inventory.json").read_text())
    model_manifest = args.models / "manifest.json"
    marker = PRIVATE / "holdout-used.json"
    if args.final:
        if not args.selection:
            raise ValueError("Freeze candidate selection before opening holdout.")
        selected = json.loads(args.selection.read_text())
        if selected.get("config_sha256") != sha(args.config) or selected.get(
            "model_manifest_sha256"
        ) != sha(model_manifest):
            raise ValueError("Frozen selection does not match this run.")
        if marker.exists():
            raise ValueError(
                "Holdout already opened. Disclose contamination and obtain fresh independent days."
            )
    selected_days = {
        day: group
        for day, group in split["days"].items()
        if group["split"] == ("holdout" if args.final else "development")
    }
    labels = {}
    for day in selected_days:
        label = json.loads((PRIVATE / "labels" / f"{day}.json").read_text())
        if (
            not label["verified"]
            or not label["reviewed_at"]
            or label["uncertainty_notes"]
        ):
            raise ValueError(
                "All selected reference days must be verified and have no unresolved questions."
            )
        if set(label["document_hashes"]) != set(selected_days[day]["document_hashes"]):
            raise ValueError("Reference source hashes differ from frozen day group.")
        labels[day] = label
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = ROOT / "artifacts/private" / f"benchmark-{timestamp}"
    output.mkdir(parents=True, exist_ok=False)
    manifest = {
        "schema_version": 1,
        "started_at": timestamp,
        "kind": "final_holdout" if args.final else "development",
        "platform": platform.platform(),
        "config_sha256": sha(args.config),
        "model_manifest_sha256": sha(model_manifest),
        "binary_sha256": sha(args.binary),
        "split_sha256": sha(split_path),
        "git_commit": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
        ).strip(),
        "source_dirty": bool(
            subprocess.check_output(
                ["git", "status", "--porcelain"], cwd=ROOT, text=True
            )
        ),
        "days": list(selected_days),
        "results": [],
        "measured": True,
    }
    write(output / "manifest.json", manifest)
    if args.final:
        # O_EXCL prevents concurrent runs from opening the final holdout twice.
        with os.fdopen(
            os.open(marker, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w"
        ) as stream:
            json.dump(
                {"opened_at": timestamp, "manifest": str(output / "manifest.json")},
                stream,
            )
    for day, group in selected_days.items():
        for capture in group["captures"]:
            predictions = []
            total_ms = 0
            per_document = []
            capture_dir = output / day / capture["id"]
            for page_id, source_hash in capture["pages"].items():
                entry = next(
                    e for e in inventory["entries"] if e["sha256"] == source_hash
                )
                image = PRIVATE / "raw" / entry["filename"]
                if sha(image) != source_hash:
                    raise ValueError("Dataset source changed since inventory.")
                destination = capture_dir / source_hash
                command = [
                    str(args.binary.resolve()),
                    "scan",
                    str(image),
                    str(destination),
                    str(args.models.resolve()),
                    str(args.config.resolve()),
                ]
                subprocess.run(command, check=True, stdout=subprocess.DEVNULL)
                run = json.loads((destination / "run.json").read_text())
                predictions.extend(run["appointments"])
                total_ms += run["total_ms"]
                per_document.append(
                    {
                        "page_id": page_id,
                        "hash": source_hash,
                        "total_ms": run["total_ms"],
                        "run_sha256": sha(destination / "run.json"),
                    }
                )
            # Comparison runs through the same shared Rust evaluator.
            combined = run.copy()
            combined["appointments"] = predictions
            combined_path = capture_dir / "combined.json"
            write(combined_path, combined)
            label_path = capture_dir / "reference-for-evaluator.json"
            reference = labels[day].copy()
            # Final access is controlled once above. The core CLI always rejects holdout.
            if args.final:
                reference["split"] = "final-authorized-by-one-shot-runner"
            write(label_path, reference)
            report_path = capture_dir / "metrics.json"
            subprocess.run(
                [
                    str(args.binary.resolve()),
                    "evaluate",
                    str(label_path),
                    str(combined_path),
                    str(report_path),
                ],
                check=True,
                stdout=subprocess.DEVNULL,
            )
            metrics = json.loads(report_path.read_text())
            manifest["results"].append(
                {
                    "day_id": day,
                    "capture_id": capture["id"],
                    "total_ms": total_ms,
                    "documents": per_document,
                    "metrics": metrics,
                }
            )
            write(output / "manifest.json", manifest)
    results = manifest["results"]
    count = len(results)
    totals = {
        key: sum(r["metrics"][key] for r in results)
        for key in [
            "reference_count",
            "predicted_count",
            "matched_count",
            "fully_correct_count",
            "missed_count",
            "invented_count",
            "date_correct",
            "start_correct",
            "end_or_duration_correct",
            "title_correct",
            "location_correct",
            "notes_correct",
            "unresolved_count",
        ]
    }
    ratio = lambda n, d: n / d if d else None
    critical = ratio(
        totals["date_correct"]
        + totals["start_correct"]
        + totals["end_or_duration_correct"],
        3 * totals["reference_count"],
    )
    precision = ratio(totals["matched_count"], totals["predicted_count"])
    recall = ratio(totals["matched_count"], totals["reference_count"])
    whole = sum(r["metrics"]["schedule_without_correction"] for r in results)
    latencies = sorted(r["total_ms"] for r in results)
    report = {
        "measured": True,
        "scope": manifest["kind"],
        "distinct_days": len(selected_days),
        "capture_count": count,
        "denominator": "complete captures; alternate photographs are correlated, not independent days",
        "days_correct_in_all_captures": sum(
            all(
                r["metrics"]["schedule_without_correction"]
                for r in results
                if r["day_id"] == day
            )
            for day in selected_days
        ),
        "counts": totals,
        "critical_field_accuracy": critical,
        "appointment_precision": precision,
        "appointment_recall": recall,
        "whole_schedules_correct": whole,
        "whole_schedule_rate": ratio(whole, count),
        "p95_daily_ms": latencies[max(0, __import__("math").ceil(0.95 * count) - 1)],
        "correction_time": "not measured",
        "peak_memory": "not measured",
        "physical_iphone17": "not measured",
        "targets": {
            "critical_fields": 0.99,
            "precision": 0.99,
            "recall": 0.99,
            "whole_schedules": 0.90,
        },
        "targets_met": all(
            v is not None and v >= target
            for v, target in [
                (critical, 0.99),
                (precision, 0.99),
                (recall, 0.99),
                (ratio(whole, count), 0.90),
            ]
        ),
    }
    write(output / "report.json", report)
    print(f"Local report: {output / 'report.json'}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
