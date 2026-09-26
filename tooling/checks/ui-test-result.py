"""Reject successful XCTest commands that did not run their requested UI tests."""

import argparse
import json
import os
import subprocess
import sys
import uuid
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tooling.utils.xcresult import command, preserved_result  # noqa: E402


def selections(arguments):
    """Keep each explicit selection; repeated xcodebuild options must not hide one."""
    result = []
    for index, argument in enumerate(arguments):
        if argument.startswith("-only-testing:"):
            result.append(argument.removeprefix("-only-testing:"))
        elif argument == "-only-testing":
            if index + 1 == len(arguments):
                raise ValueError("Missing -only-testing value")
            result.append(arguments[index + 1])
    for value in result:
        parts = value.removesuffix("()").split("/")
        if not 1 <= len(parts) <= 3 or any(not part or part.startswith("-") for part in parts):
            raise ValueError("Expected a test target, class or exact XCTest method")
    return list(dict.fromkeys(value.removesuffix("()") for value in result))


def selection_status(summary, tests, required):
    cases = []

    def visit(nodes):
        for node in nodes:
            if node.get("nodeType") == "Test Case":
                cases.append(node)
            visit(node.get("children", []))

    visit(tests.get("testNodes", []))
    identities = []
    for case in cases:
        url = urlsplit(case.get("nodeIdentifierURL", ""))
        parts = unquote(url.path).strip("/").split("/")
        if url.scheme != "test" or len(parts) < 4:
            continue
        target, suite, method = parts[-3:]
        if case.get("nodeIdentifier") != f"{suite}/{method}()":
            continue
        identities.append((f"{target}/{suite}/{method}", case.get("result")))
    total = summary.get("totalTestCount")
    complete = (
        summary.get("result") == "Passed"
        and type(total) is int
        and total > 0
        and summary.get("passedTests") == total
        and summary.get("failedTests") == 0
        and summary.get("skippedTests") == 0
        and len(identities) == len(cases) == total
        and len({name for name, _ in identities}) == total
        and all(result == "Passed" for _, result in identities)
    )
    requests = []
    for required_test in required:
        matches = [
            name
            for name, _ in identities
            if name == required_test or name.startswith(required_test + "/")
        ]
        requests.append(
            {"selection": required_test, "executed_tests": matches, "present": bool(matches)}
        )
    return {
        "passed": complete and all(request["present"] for request in requests),
        "complete_run_passed": complete,
        "executed_tests": [name for name, _ in identities],
        "requested_tests": requests,
        "suite_enumeration_verified": False,
    }


def verify(bundle, output, required, run=command):
    if output.resolve().is_relative_to(bundle.resolve()):
        raise ValueError("Verification must remain outside the retained result")
    output.mkdir(parents=True, mode=0o700, exist_ok=False)
    with preserved_result(bundle) as (working, original):
        summary = json.loads(run(["get", "test-results", "summary", "--path", str(working)]))
        tests = json.loads(run(["get", "test-results", "tests", "--path", str(working)]))
        (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        (output / "tests.json").write_text(json.dumps(tests, indent=2) + "\n")
    report = selection_status(summary, tests, required)
    report["source_result"] = {
        "bundle": str(bundle.resolve()),
        "files": original,
        "unchanged": True,
    }
    (output / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def execute(arguments):
    required = selections(arguments)
    indexes = [i for i, arg in enumerate(arguments) if arg == "-resultBundlePath"]
    if len(indexes) > 1 or any(arg.startswith("-resultBundlePath=") for arg in arguments):
        raise ValueError("Use exactly one separate -resultBundlePath value")
    if indexes:
        index = indexes[0]
        if index + 1 == len(arguments) or arguments[index + 1].startswith("-"):
            raise ValueError("Missing -resultBundlePath value")
        bundle = Path(arguments[index + 1])
        if not bundle.is_absolute():
            bundle = ROOT / bundle
    else:
        folder = ROOT / ".local/runs" / ("native-ui-" + uuid.uuid4().hex)
        folder.mkdir(parents=True, mode=0o700)
        bundle = folder / "result.xcresult"
        arguments = [*arguments, "-resultBundlePath", str(bundle)]
    output = bundle.with_name(bundle.name + ".verification")
    if bundle.exists() or bundle.is_symlink() or output.exists() or output.is_symlink():
        raise ValueError("Result and verification destinations must be new")
    invocation = ["xcodebuild", "test-without-building", *arguments]
    status = subprocess.run(invocation, cwd=ROOT).returncode
    if not bundle.is_dir():
        print("XCTest did not produce a result bundle", file=sys.stderr)
        return status or 1
    report = verify(bundle, output, required)
    (output / "execution.json").write_text(
        json.dumps({"command": invocation, "exit_code": status}, indent=2) + "\n"
    )
    print(f"UI execution evidence: {output}", flush=True)
    if not report["passed"]:
        print("UI test selection did not execute completely and successfully", file=sys.stderr)
        for request in report["requested_tests"]:
            if not request["present"]:
                print("Missing requested test: " + request["selection"], file=sys.stderr)
    return status or (0 if report["passed"] else 1)


def main():
    os.umask(0o077)
    if len(sys.argv) > 1 and sys.argv[1] == "run":
        raise SystemExit(execute(sys.argv[2:]))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--only-test", action="append", default=[])
    args = parser.parse_args()
    required = selections(["-only-testing:" + value for value in args.only_test])
    report = verify(args.bundle, args.output, required)
    print(
        json.dumps(
            {key: value for key, value in report.items() if key != "source_result"}, indent=2
        )
    )
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
