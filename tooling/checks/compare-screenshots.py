#!/usr/bin/env python3
"""Exact fixed-fixture screenshot comparison, excluding declared system pixels."""

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


def compare(baseline, candidate, *, ignore_top=0):
    with Image.open(baseline) as original, Image.open(candidate) as current:
        if original.size != current.size:
            raise ValueError(f"Screenshot dimensions differ: {original.size} / {current.size}")
        if not 0 <= ignore_top < original.height:
            raise ValueError("Excluded status bar must leave app content for comparison")
        difference = ImageChops.difference(original.convert("RGB"), current.convert("RGB"))
        mask = ImageChops.lighter(
            ImageChops.lighter(*difference.split()[:2]), difference.split()[2]
        )
        if ignore_top:
            ImageDraw.Draw(mask).rectangle((0, 0, original.width - 1, ignore_top - 1), fill=0)
        return {
            "passed": mask.getbbox() is None,
            "size": list(original.size),
            "ignored_top_pixels": ignore_top,
            "different_pixels": original.width * original.height - mask.histogram()[0],
            "difference_bounds": mask.getbbox(),
            "baseline_sha256": hashlib.sha256(Path(baseline).read_bytes()).hexdigest(),
            "candidate_sha256": hashlib.sha256(Path(candidate).read_bytes()).hexdigest(),
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--ignore-top", type=int, default=0)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    report = compare(args.baseline, args.candidate, ignore_top=args.ignore_top)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
