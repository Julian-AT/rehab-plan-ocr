"""Paired, interleaved desktop microbenchmark; not a shipping-device qualification."""

import argparse
import hashlib
import json
import platform
import statistics
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCES = ["CalendarEvent.swift", "AgendaProjection.swift"]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--baseline", default="1a20779")
    parser.add_argument("--pairs", type=int, default=5)
    parser.add_argument("--iterations", type=int, default=3)
    args = parser.parse_args()
    if min(args.pairs, args.iterations) < 1:
        raise ValueError("Pairs and iterations must be positive")
    revision = subprocess.check_output(
        ["git", "rev-parse", "--verify", args.baseline + "^{commit}"], cwd=ROOT, text=True
    ).strip()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    benchmark = Path(__file__).with_name("AgendaProjectionBenchmark.swift")
    compiler = subprocess.check_output(
        ["swiftc", "--version"], text=True, stderr=subprocess.STDOUT
    ).strip()
    sources = {}
    for variant in ["baseline", "candidate"]:
        directory = output / variant
        directory.mkdir()
        for name in SOURCES:
            path = "apps/ios/Features/Agenda/" + name
            content = (
                subprocess.check_output(["git", "show", f"{revision}:{path}"], cwd=ROOT)
                if variant == "baseline"
                else (ROOT / path).read_bytes()
            )
            (directory / name).write_bytes(content)
        sources[variant] = {name: sha(directory / name) for name in SOURCES}
        subprocess.run(
            [
                "swiftc",
                "-O",
                "-swift-version",
                "6",
                *[str(directory / name) for name in SOURCES],
                str(benchmark),
                "-o",
                str(directory / "probe"),
            ],
            check=True,
        )
    report = {
        "kind": "desktop-projection-microbenchmark",
        "qualified": False,
        "baseline_revision": revision,
        "platform": platform.platform(),
        "compiler": compiler,
        "source_hashes": sources,
        "benchmark_sha256": sha(benchmark),
        "records": [],
    }
    report_path = output / "report.json"
    for pair in range(args.pairs):
        for variant in ["baseline", "candidate"] if pair % 2 == 0 else ["candidate", "baseline"]:
            result = json.loads(
                subprocess.check_output(
                    [str(output / variant / "probe"), str(args.iterations)], text=True, timeout=120
                )
            )
            report["records"].append(result | {"variant": variant, "pair": pair})
            report_path.write_text(json.dumps(report, indent=2) + "\n")
    if len({row["checksum"] for row in report["records"]}) != 1:
        raise ValueError("The two implementations did not produce the same result count")
    for variant in ["baseline", "candidate"]:
        rows = [row for row in report["records"] if row["variant"] == variant]
        print(
            variant,
            "construction + projection median milliseconds:",
            statistics.median(row["construction_and_projection_milliseconds"] for row in rows),
        )
    print(f"Synthetic desktop evidence only: {report_path}")


if __name__ == "__main__":
    main()
