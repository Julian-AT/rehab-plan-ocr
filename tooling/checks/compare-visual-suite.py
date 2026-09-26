"""Compare every retained calendar reference with fresh XCTest attachments.

Only the declared system-status pixels are excluded. Candidate images can never
replace the committed baseline. A missing, duplicate or failed capture fails.
"""

import argparse
import hashlib
import html
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tooling/dev"))
import workspace  # noqa: E402

sys.path.insert(0, str(ROOT))
from tooling.utils.xcresult import command, preserved_result  # noqa: E402

BASELINE = ROOT / "docs/product/visual-baseline"
spec = importlib.util.spec_from_file_location(
    "comparison", Path(__file__).with_name("compare-screenshots.py")
)
comparison = importlib.util.module_from_spec(spec)
spec.loader.exec_module(comparison)
CAPTURE_TESTS = (
    "CalmCalendarTests/testMutedPaletteCardsListAndLegend()",
    "CalmCalendarTests/testLargeCalendarText()",
    "CalmCalendarTests/testVisualFinishedDay()",
)


def capture_owner(name):
    if name.startswith("large-"):
        return CAPTURE_TESTS[1]
    if name.startswith("past-events-"):
        return CAPTURE_TESTS[2]
    if name.startswith(("cards-", "list-", "legend-")):
        return CAPTURE_TESTS[0]
    raise ValueError(f"No declared capture test for {name}")


def belongs_to_capture(identifier, url, expected):
    return (
        identifier == expected
        and isinstance(url, str)
        and url.startswith("test://")
        and url.endswith("/TermineUITests/" + expected.removesuffix("()"))
    )


def capture_test_status(summary, tests):
    cases = []

    def visit(nodes):
        for node in nodes:
            if node.get("nodeType") == "Test Case":
                cases.append(node)
            visit(node.get("children", []))

    visit(tests.get("testNodes", []))
    captures = []
    for identifier in CAPTURE_TESTS:
        matches = [
            case
            for case in cases
            if belongs_to_capture(
                case.get("nodeIdentifier"), case.get("nodeIdentifierURL"), identifier
            )
        ]
        captures.append(
            {
                "identifier": identifier,
                "results": [case.get("result") for case in matches],
                "passed": len(matches) == 1 and matches[0].get("result") == "Passed",
            }
        )
    total = summary.get("totalTestCount")
    complete = (
        summary.get("result") == "Passed"
        and type(total) is int
        and total >= len(CAPTURE_TESTS)
        and summary.get("passedTests") == total
        and summary.get("failedTests") == 0
        and summary.get("skippedTests") == 0
    )
    return {
        "passed": complete and all(case["passed"] for case in captures),
        "complete_run_passed": complete,
        "required_tests": captures,
    }


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compare_suite(baseline, attachments, output):
    catalog = json.loads((baseline / "baseline.json").read_text())
    manifest = json.loads((attachments / "manifest.json").read_text())
    output.mkdir(exist_ok=False)
    images = []
    for entry in catalog["images"]:
        name = entry["file"]
        if Path(name).name != name or sha(baseline / name) != entry["sha256"]:
            raise ValueError("Baseline identity differs from its preserved catalog")
        pattern = re.compile(r"^calm-" + re.escape(Path(name).stem) + r"(?:_|\.png$)")
        matches = [
            (test, attachment)
            for test in manifest
            for attachment in test["attachments"]
            if pattern.match(attachment["suggestedHumanReadableName"])
        ]
        result = {"baseline": name, "passed": False}
        if len(matches) != 1:
            result["error"] = f"Expected exactly one capture, found {len(matches)}"
        elif not belongs_to_capture(
            matches[0][0].get("testIdentifier"),
            matches[0][0].get("testIdentifierURL"),
            capture_owner(name),
        ):
            result["error"] = "Capture does not belong to its declared test"
        elif matches[0][1]["isAssociatedWithFailure"]:
            result["error"] = "Capture belongs to a failed test"
        else:
            attachment = matches[0][1]
            filename = attachment["exportedFileName"]
            if Path(filename).name != filename:
                raise ValueError("Attachment filename escapes its export directory")
            candidate = attachments / filename
            if not candidate.resolve().is_relative_to(attachments.resolve()):
                raise ValueError("Attachment escapes its export directory")
            shutil.copyfile(candidate, output / name)
            try:
                result.update(comparison.compare(baseline / name, candidate, ignore_top=160))
            except ValueError as error:
                result["error"] = str(error)
            result["attachment"] = attachment
        images.append(result)
    return {
        "passed": bool(images) and all(image["passed"] for image in images),
        "baseline_catalog_sha256": sha(baseline / "baseline.json"),
        "attachments_manifest_sha256": sha(attachments / "manifest.json"),
        "reference_count": len(images),
        "matching_images": sum(image["passed"] for image in images),
        "ignored_top_pixels": 160,
        "full_app_regression_qualified": False,
        "images": images,
    }


def write_review(report, baseline, output):
    references = output / "references"
    references.mkdir(exist_ok=False)
    sections = []
    for item in report["images"]:
        name = item["baseline"]
        shutil.copyfile(baseline / name, references / name)
        escaped = html.escape(name, quote=True)
        status = "Pixelgleich" if item["passed"] else "Abweichung – prüfen"
        detail = html.escape(
            str(item.get("error", f"{item.get('different_pixels', 0)} abweichende Pixel"))
        )
        sections.append(
            f'<section><h2>{escaped}</h2><p><strong>{status}</strong> · {detail}</p><div class="pair">'
            f'<figure><figcaption>Bestehende Referenz</figcaption><a href="references/{escaped}">'
            f'<img loading="lazy" alt="Referenz {escaped}" src="references/{escaped}"></a></figure>'
            f'<figure><figcaption>Aktuelle Simulatoraufnahme</figcaption><a href="previews/{escaped}">'
            f'<img loading="lazy" alt="Aktuell {escaped}" src="previews/{escaped}"></a></figure>'
            "</div></section>"
        )
    document = (
        '<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width">'
        "<title>Kalenderansichten vergleichen</title><style>"
        "body{font:18px system-ui,sans-serif;color:#161616;background:#fafafa;max-width:1000px;margin:32px auto;padding:0 20px}"
        "h1{font-size:2rem}h2{font-size:1.25rem}section{border-top:1px solid #bbb;margin-top:32px}"
        ".pair{display:flex;gap:24px}figure{margin:0;width:50%}img{width:100%;height:auto}figcaption{padding:12px 0}"
        "a{color:#0645ad}a:focus-visible{outline:3px solid #0645ad}</style>"
        "<h1>Kalenderansichten vergleichen</h1>"
        f"<p>{report['matching_images']} von {report['reference_count']} Aufnahmen sind unterhalb der Systemstatusleiste pixelgleich.</p>"
        "<p>Die übrigen Ansichten benötigen Prüfung. Die Originalreferenzen bleiben erhalten. "
        "Dieser Vergleich ist keine Freigabe der gesamten App oder eines Geräteupdates.</p>"
        "<p>Bilder anklicken, um sie in voller Größe zu öffnen. Alle Bilder enthalten erfundene Termine.</p>"
        + "".join(sections)
        + "</html>"
    )
    (output / "review.html").write_text(document)


def export_evidence(bundle, output, run=command):
    if output.resolve().is_relative_to(bundle.resolve()):
        raise ValueError("Visual evidence must remain outside the source result bundle")
    with preserved_result(bundle) as (working, source_files):
        summary = json.loads(
            run(
                [
                    "get",
                    "test-results",
                    "summary",
                    "--path",
                    str(working),
                ]
            )
        )
        (output / "test-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        tests = json.loads(run(["get", "test-results", "tests", "--path", str(working)]))
        (output / "test-tree.json").write_text(json.dumps(tests, indent=2) + "\n")
        run(
            [
                "export",
                "attachments",
                "--path",
                str(working),
                "--output-path",
                str(output / "attachments"),
            ]
        )
    (output / "source-result.json").write_text(
        json.dumps(
            {"bundle": str(bundle.resolve()), "files": source_files, "unchanged": True}, indent=2
        )
        + "\n"
    )
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--xcresult", type=Path)
    mode.add_argument("--capture", action="store_true")
    parser.add_argument("--run", type=Path, required=True)
    args = parser.parse_args()
    output = args.run.resolve()
    if not output.is_relative_to(ROOT / ".local/runs"):
        raise ValueError("Use a new .local/runs directory")
    if args.xcresult and output.is_relative_to(args.xcresult.resolve()):
        raise ValueError("Visual evidence must remain outside the source result bundle")
    output.mkdir(parents=True, exist_ok=False)
    evaluator_revision = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
    ).strip()
    before = source_snapshot() if args.capture else None
    capture_status = None
    result_bundle = args.xcresult
    if args.capture:
        result_bundle = output / "result.xcresult"
        with (output / "capture.log").open("w") as log:
            capture_status = subprocess.run(
                [
                    "sh",
                    "tooling/checks/test-native-ui.sh",
                    *[
                        "-only-testing:TermineUITests/" + test.removesuffix("()")
                        for test in CAPTURE_TESTS
                    ],
                    "-resultBundlePath",
                    str(result_bundle),
                ],
                cwd=ROOT,
                env={**os.environ, "REHA_UI_MEDIA": "0"},
                stdout=log,
                stderr=subprocess.STDOUT,
            ).returncode
        (output / "capture.json").write_text(
            json.dumps(
                {
                    "exit_code": capture_status,
                    "sources": before,
                    "sources_unchanged": before == source_snapshot(),
                },
                indent=2,
            )
            + "\n"
        )
    summary = export_evidence(result_bundle, output)
    report = compare_suite(BASELINE, output / "attachments", output / "previews")
    report["capture_tests"] = capture_test_status(
        summary, json.loads((output / "test-tree.json").read_text())
    )
    report["tests_passed"] = report["capture_tests"]["passed"]
    report["test_tree_sha256"] = sha(output / "test-tree.json")
    report["passed"] = report["passed"] and report["tests_passed"]
    # A supplied historical bundle does not identify the app with today's checkout.
    report["capture_mode"] = "fresh" if args.capture else "provided-result"
    report["evaluator_revision"] = evaluator_revision
    report["source_revision"] = evaluator_revision if args.capture else None
    if args.capture:
        report["sources"] = before
        report["capture_exit_code"] = capture_status
        report["sources_unchanged"] = before == source_snapshot()
        report["passed"] = report["passed"] and capture_status == 0 and report["sources_unchanged"]
    report["comparator_sha256"] = sha(Path(__file__))
    report["pixel_comparator_sha256"] = sha(Path(__file__).with_name("compare-screenshots.py"))
    report["xcresult"] = str(result_bundle.resolve())
    report["source_result_receipt_sha256"] = sha(output / "source-result.json")
    report["result_reader_sha256"] = sha(ROOT / "tooling/utils/xcresult.py")
    if args.capture:
        app = (
            workspace.location("ios", ROOT)
            / "DerivedData/Build/Products/Debug-iphonesimulator/Laßnitzhöhe.app"
        )
        if (app / "Termine.debug.dylib").is_file():
            report["app_binary_sha256"] = sha(app / "Termine.debug.dylib")
    (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    write_review(report, BASELINE, output)
    print(json.dumps({k: v for k, v in report.items() if k not in {"images", "sources"}}, indent=2))
    if not report["passed"]:
        raise SystemExit(1)


def source_snapshot():
    names = (
        subprocess.check_output(
            [
                "git",
                "ls-files",
                "--cached",
                "--others",
                "--exclude-standard",
                "-z",
                "--",
                "apps/ios",
                "packages",
                "tooling/build",
                "tooling/checks/test-native-ui.sh",
                "tooling/checks/native-simulator.py",
                "docs/third-party/runtime-inventory.json",
                "config",
                "ml/registry/runtime",
                "Cargo.toml",
                "Cargo.lock",
                "rust-toolchain.toml",
            ],
            cwd=ROOT,
        )
        .decode()
        .split("\0")
    )
    # Documentation edits do not change the tested app. Runtime/test resources,
    # source code, project configuration and dependency identities still do.
    return {
        name: sha(ROOT / name) for name in sorted(set(names)) if name and Path(name).suffix != ".md"
    }


if __name__ == "__main__":
    main()
