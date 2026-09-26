"""Run an exploratory local OCR baseline on a conversion manifest.

This is a diagnostic run, not accuracy evaluation: it requires no labels, never
marks predictions as ground truth, and does not open a frozen final holdout.
Content-bearing artifacts and the static review report belong in private storage.
"""

import argparse
import hashlib
import html
import json
import math
import platform
import re
import statistics
import subprocess
import time
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def summarize(run):
    appointments = run["appointments"]
    observations = run["observations"]
    issues = run["issues"] + [i for a in appointments for i in a["issues"]]
    unassigned = set(run["unassigned"])
    return {
        "appointments": len(appointments),
        "observations": len(observations),
        "missing_date": sum(not a["date"] for a in appointments),
        "missing_start": sum(not a["start"] for a in appointments),
        "missing_end_or_duration": sum(
            not a["end"] and not a["duration_minutes"] for a in appointments
        ),
        "empty_title": sum(not a["title"].strip() for a in appointments),
        "with_therapist": sum(bool(a.get("therapist")) for a in appointments),
        "multi_observation_therapist": sum(
            len(a["provenance"].get("therapist", [])) > 1 for a in appointments
        ),
        "remaining_new_markers": sum(
            bool(
                re.search(
                    r"\*\s*neu\b",
                    " ".join(
                        a.get(f, "")
                        for f in ("title", "location", "therapist", "notes")
                    ),
                    re.IGNORECASE,
                )
            )
            for a in appointments
        ),
        "blocking_issues": sum(i["blocking"] for i in issues),
        "issue_codes": dict(Counter(i["code"] for i in issues)),
        "unassigned_observations": len(unassigned),
        "unassigned_time_observations": sum(
            o["id"] in unassigned
            and bool(re.search(r"\b(?:[01]?\d|2[0-3]):[0-5]\d\b", o["text"]))
            for o in observations
        ),
        "scores_below_0_8": sum(
            o["score"] is not None and o["score"] < 0.8 for o in observations
        ),
        "total_ms": run["total_ms"],
    }


def review_html(output, results):
    escape = lambda value: html.escape(str(value if value is not None else "—"))
    sections = []
    for result in results:
        identifier = result["id"]
        if result["status"] != "complete":
            sections.append(
                f"<h2>{escape(identifier)}: failed — see local error log</h2>"
            )
            continue
        run = json.loads((output / identifier / "run.json").read_text())
        rows = "".join(
            "<tr>"
            + "".join(
                f"<td>{escape(a.get(field))}</td>"
                for field in (
                    "date",
                    "start",
                    "end",
                    "duration_minutes",
                    "title",
                    "location",
                    "therapist",
                    "notes",
                )
            )
            + "</tr>"
            for a in run["appointments"]
        )
        observations = "\n".join(f"{o['id']}: {o['text']}" for o in run["observations"])
        sections.append(
            f"<section><h2>{escape(identifier)} · {escape(result['filename'])}</h2>"
            f"<p>{escape(json.dumps(result['diagnostics']))}</p>"
            f'<p><a href="{identifier}/run.json">Run JSON</a> · '
            f'<a href="{identifier}/original.png">Full-resolution image</a></p>'
            '<div class="comparison">'
            f'<a href="{identifier}/original.png"><img loading="lazy" '
            f'src="{identifier}/original.png" alt="Source for {escape(identifier)}"></a>'
            '<div class="table"><table><thead><tr>'
            "<th>Date</th><th>Start</th><th>End</th><th>Minutes</th><th>Title</th>"
            "<th>Location</th><th>Therapeut</th><th>Notes</th>"
            f"</tr></thead><tbody>{rows}</tbody></table></div></div>"
            f"<details><summary>Raw OCR observations</summary><pre>{escape(observations)}</pre></details>"
            "</section>"
        )
    (output / "review.html").write_text(
        '<!doctype html><html lang="en"><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; '
        "img-src 'self' data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'\">"
        "<title>Local OCR baseline</title><style>"
        "body{font:14px system-ui;margin:24px;color:#18181b;background:white}"
        "section{border-top:1px solid #ddd;margin-top:32px;padding-top:12px}"
        ".comparison{display:grid;grid-template-columns:40% 60%;gap:12px}"
        "img{width:100%;height:auto}.table{overflow:auto}table{border-collapse:collapse}"
        "td,th{padding:8px;text-align:left;border:1px solid #ddd;vertical-align:top}"
        "p,pre{white-space:pre-wrap;overflow-wrap:anywhere}details{margin-top:16px}"
        "@media(max-width:900px){.comparison{display:block}}"
        "</style><h1>Local OCR baseline</h1>"
        "<p>Unverified predictions. Compare every row against the image before using "
        "these results as reference annotations. No accuracy score is available. "
        "Counts of missing fields and unassigned times are diagnostics; they do not "
        "measure missed appointments. OCR scores are uncalibrated engine signals.</p>"
        '<p><a href="report.json">Summary report</a> · <a href="manifest.json">Run manifest</a></p>'
        + "".join(sections)
        + "</html>\n"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("conversion", type=Path, help="Private conversion manifest")
    parser.add_argument("output", type=Path, help="New private results directory")
    parser.add_argument("--models", type=Path, default=ROOT / "models/private/small")
    parser.add_argument("--binary", type=Path, default=ROOT / "target/release/reha")
    parser.add_argument("--config", type=Path)
    args = parser.parse_args()
    conversion = json.loads(args.conversion.read_text())
    if conversion["status"] != "complete" or not conversion["entries"]:
        raise ValueError("Conversion is incomplete or empty.")
    args.output.mkdir(parents=True, exist_ok=False)
    manifest = {
        "schema_version": 1,
        "kind": "exploratory_unverified",
        "started_at": datetime.now(timezone.utc).isoformat(),
        "platform": platform.platform(),
        "conversion_sha256": digest(args.conversion),
        "model_manifest_sha256": digest(args.models / "manifest.json"),
        "binary_sha256": digest(args.binary),
        "runner_sha256": digest(Path(__file__)),
        "config": json.loads(args.config.read_text())
        if args.config
        else "CLI defaults; recorded per run",
        "git_commit": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
        ).strip(),
        "source_dirty": bool(
            subprocess.check_output(
                ["git", "status", "--porcelain"], cwd=ROOT, text=True
            )
        ),
        "network_enforcement": "sandbox-exec deny network*"
        if platform.system() == "Darwin"
        else "not enforced by this runner",
        "results": [],
    }
    write_json(args.output / "manifest.json", manifest)
    for number, entry in enumerate(conversion["entries"], 1):
        image = Path(entry["png"]["path"])
        if digest(image) != entry["png"]["sha256"]:
            raise ValueError("Converted image changed since manifest was recorded.")
        if any(digest(Path(p)) != entry["source_sha256"] for p in entry["sources"]):
            raise ValueError("Original image changed since conversion.")
        identifier = f"document-{number:02d}"
        destination = args.output / identifier
        command = [
            str(args.binary.resolve()),
            "scan",
            str(image),
            str(destination),
            str(args.models.resolve()),
        ]
        if args.config:
            command.append(str(args.config.resolve()))
        if platform.system() == "Darwin":
            command = [
                "/usr/bin/sandbox-exec",
                "-p",
                "(version 1) (allow default) (deny network*)",
                *command,
            ]
        started = time.perf_counter()
        destination.mkdir()
        result = {
            "id": identifier,
            "filename": image.name,
            "original_sha256": entry["source_sha256"],
            "png_sha256": entry["png"]["sha256"],
        }
        with (destination / "process.log").open("w") as log:
            try:
                subprocess.run(command, check=True, stdout=log, stderr=log, timeout=180)
                run = json.loads((destination / "run.json").read_text())
                result.update(
                    status="complete",
                    diagnostics=summarize(run),
                    run_sha256=digest(destination / "run.json"),
                )
            except (subprocess.SubprocessError, OSError, ValueError) as error:
                result.update(status="failed", failure=type(error).__name__)
        result["process_wall_ms"] = round((time.perf_counter() - started) * 1000)
        manifest["results"].append(result)
        write_json(args.output / "manifest.json", manifest)
        print(f"{identifier}: {result['status']}", flush=True)
    results = manifest["results"]
    successful = [r["diagnostics"] for r in results if r["status"] == "complete"]
    latencies = sorted(r["total_ms"] for r in successful)
    totals = (
        {
            key: sum(r[key] for r in successful)
            for key in successful[0]
            if key not in {"issue_codes", "total_ms"}
        }
        if successful
        else {}
    )
    report = {
        "kind": "exploratory_unverified",
        "unique_images": len(results),
        "completed": len(successful),
        "failed": len(results) - len(successful),
        "counts": totals,
        "documents_with_missing_dates": sum(r["missing_date"] > 0 for r in successful),
        "documents_with_blocking_issues": sum(
            r["blocking_issues"] > 0 for r in successful
        ),
        "documents_without_appointments": sum(
            r["appointments"] == 0 for r in successful
        ),
        "cold_pipeline_ms": {
            "median": statistics.median(latencies),
            "p95_nearest_rank": latencies[math.ceil(0.95 * len(latencies)) - 1],
            "max": max(latencies),
        }
        if latencies
        else None,
        "accuracy": None,
        "accuracy_reason": "No verified reference annotations; no precision, recall or critical-field accuracy claim.",
        "limitations": [
            "Unique images are not yet verified distinct treatment days.",
            "Unassigned times can include printing timestamps; treat as review hints.",
            "Cold CLI CPU timings include model load and pipeline artifacts, excluding HEIC conversion.",
            "Physical iPhone performance, peak memory and correction effort are unmeasured.",
            "No model tuning, training or final holdout evaluation performed.",
        ],
    }
    write_json(args.output / "report.json", report)
    review_html(args.output, results)
    print(json.dumps(report, indent=2))
    if report["failed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
