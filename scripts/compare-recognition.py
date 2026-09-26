"""Compare local executables on approved photos, including result serialization.

Each scan starts a new process. These are desktop process-start measurements,
never warm-model or physical-iPhone evidence. Original images use bounded
temporary storage; only private JSON results and logs are retained.
"""

import argparse
import json
import math
import platform
import re
import statistics
import subprocess
import tempfile
import time
from pathlib import Path

from benchmark import preflight, sha, summarize, write


def timing(values):
    ordered = sorted(values)
    return {
        "count": len(ordered),
        "median_ms": statistics.median(ordered) if ordered else None,
        "p95_ms": ordered[math.ceil(len(ordered) * 0.95) - 1] if ordered else None,
        "maximum_ms": max(ordered, default=None),
    }


def compare(base, candidate):
    """Count reductions cannot hide a newly wrong date/time on another row."""
    old = {(r["source_hash"], r.get("repeat", 0)): r for r in base}
    new_critical, new_invented, new_false_acceptances = [], [], []
    for row in candidate:
        prior = old[(row["source_hash"], row.get("repeat", 0))]["metrics"]
        current = row["metrics"]
        for key, destination in [
            ("critical_errors", new_critical),
            ("critical_false_acceptances", new_false_acceptances),
        ]:
            destination.extend(
                f"{row['source_hash']}:{field}"
                for field in sorted(set(current[key]) - set(prior[key]))
            )
        if current["invented_count"] > prior["invented_count"]:
            new_invented.append(row["source_hash"])
    a = summarize([r for r in base if r.get("repeat", 0) == 0])
    b = summarize([r for r in candidate if r.get("repeat", 0) == 0])
    ta, tb = timing([r["wall_ms"] for r in base]), timing([r["wall_ms"] for r in candidate])
    improved = b["counts"]["field_corrections_needed"] < a["counts"][
        "field_corrections_needed"
    ] and (
        b["counts"]["fully_correct_count"] > a["counts"]["fully_correct_count"]
        or b["fully_correct_photos"] > a["fully_correct_photos"]
    )
    speed = tb["median_ms"] <= ta["median_ms"] and tb["p95_ms"] <= ta["p95_ms"]
    return {
        "new_critical_errors": new_critical,
        "photos_with_additional_invented_rows": new_invented,
        "new_critical_false_acceptances": new_false_acceptances,
        "desktop_quality_improved": improved,
        "desktop_timing_not_slower": speed,
        "eligible_for_iphone_comparison": bool(
            improved and speed and not (new_critical or new_invented or new_false_acceptances)
        ),
        "eligible_as_default": False,
        "default_blocker": "Physical iPhone cold/warm, thermal and memory evidence required.",
    }


def run(root, suite_path, destination, evaluator, canary, repeats):
    split, refs = preflight(root, evaluator)
    suite = json.loads(suite_path.read_text())
    candidates = suite["candidates"]
    names = [c["name"] for c in candidates]
    if (
        not candidates
        or len(set(names)) != len(names)
        or not 1 <= repeats <= 5
        or any(not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}", n) for n in names)
    ):
        raise ValueError("Unique candidates and one to five process repeats required.")
    for candidate in candidates:
        for key in ["binary", "models", "config"]:
            candidate[key] = str(Path(candidate[key]).resolve())
        for key in ["binary", "config"]:
            digest = sha(Path(candidate[key]))
            expected = candidate.get(key + "_sha256")
            if expected and expected != digest:
                raise ValueError("Frozen executable/configuration changed.")
            candidate[key + "_sha256"] = digest
        candidate["model_manifest_sha256"] = sha(Path(candidate["models"]) / "manifest.json")
    inventory = json.loads((root / "inventory.json").read_text())["entries"]
    if canary:
        selected = suite["canary_hashes"]
        if len(selected) != 5 or len(set(selected)) != 5:
            raise ValueError("Declare five distinct representative photos before running.")
        inventory = [e for e in inventory if e["sha256"] in selected]
        if len(inventory) != 5:
            raise ValueError("Canary photo absent from inventory.")
    destination.mkdir(parents=True, exist_ok=False)
    report = {
        "platform": platform.platform(),
        "measurement": "desktop_process_start_to_serialized_result",
        "physical_iphone_measurement": False,
        "independent_final_test": False,
        "canary": canary,
        "folds": split,
        "evaluator_sha256": sha(evaluator),
        "reference_sha256": {h: sha(p) for h, p in refs.items()},
        "candidates": candidates,
        "results": {name: [] for name in names},
    }
    for i, entry in enumerate(inventory):
        digest = entry["sha256"]
        source = (root / "raw" / entry["filename"]).resolve()
        if not source.is_relative_to((root / "raw").resolve()) or sha(source) != digest:
            raise ValueError("Original path or checksum mismatch.")
        # Rotate execution order to reduce systematic ordering bias.
        ordered = candidates[i % len(candidates) :] + candidates[: i % len(candidates)]
        for repeat in range(repeats):
            for candidate in ordered:
                name = candidate["name"]
                for key in ["binary", "config"]:
                    if sha(Path(candidate[key])) != candidate[key + "_sha256"]:
                        raise ValueError("Candidate changed during measurement.")
                if (
                    sha(Path(candidate["models"]) / "manifest.json")
                    != candidate["model_manifest_sha256"]
                ):
                    raise ValueError("Model manifest changed during measurement.")
                if (
                    sha(evaluator) != report["evaluator_sha256"]
                    or sha(refs[digest]) != report["reference_sha256"][digest]
                ):
                    raise ValueError(
                        "Evaluation executable or reference changed during measurement."
                    )
                output = destination / name / digest / str(repeat)
                output.mkdir(parents=True)
                with tempfile.TemporaryDirectory(prefix="reha-comparison-") as temporary:
                    with (output / "process.log").open("w") as log:
                        started = time.perf_counter()
                        process = subprocess.run(
                            [
                                candidate["binary"],
                                "scan",
                                str(source),
                                temporary,
                                candidate["models"],
                                candidate["config"],
                            ],
                            stdout=log,
                            stderr=log,
                            timeout=75,
                            check=False,
                        )
                        elapsed = (time.perf_counter() - started) * 1000
                    if process.returncode:
                        write(destination / "summary.json", report)
                        raise ValueError(
                            f"Candidate {name} failed; inspect its private process log."
                        )
                    run_path = Path(temporary) / "run.json"
                    prediction = json.loads(run_path.read_text())
                    write(output / "run.json", prediction)
                subprocess.run(
                    [
                        str(evaluator),
                        "evaluate",
                        str(refs[digest]),
                        str(output / "run.json"),
                        str(output / "metrics.json"),
                    ],
                    check=True,
                    capture_output=True,
                )
                row = {
                    "source_hash": digest,
                    "repeat": repeat,
                    "wall_ms": elapsed,
                    "total_ms": prediction["total_ms"],
                    "metrics": json.loads((output / "metrics.json").read_text()),
                }
                report["results"][name].append(row)
                write(destination / "summary.json", report)
                print(
                    f"Photo {i + 1}/{len(inventory)}, {name}, process {repeat + 1}: complete",
                    flush=True,
                )
    report["summaries"] = {}
    for name, rows in report["results"].items():
        # Accuracy counts each real photo once, regardless of process repeats.
        first = [r for r in rows if r["repeat"] == 0]
        report["summaries"][name] = {
            "quality": summarize(first),
            "timing": timing([r["wall_ms"] for r in rows]),
            "critical_errors": sum(len(r["metrics"]["critical_errors"]) for r in first),
            "critical_false_acceptances": sum(
                len(r["metrics"]["critical_false_acceptances"]) for r in first
            ),
        }
    report["comparisons"] = {
        name: compare(
            report["results"][names[0]],
            report["results"][name],
        )
        for name in names[1:]
    }
    write(destination / "summary.json", report)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for argument in ["root", "suite", "destination", "evaluator"]:
        parser.add_argument("--" + argument, type=Path, required=True)
    parser.add_argument("--canary", action="store_true")
    parser.add_argument("--repeats", type=int, default=1)
    args = parser.parse_args()
    run(
        args.root.resolve(),
        args.suite,
        args.destination,
        args.evaluator.resolve(),
        args.canary,
        args.repeats,
    )
