"""Collect small failure evidence while preserving the complete source xcresult."""

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path


def inventory(root):
    files = {}
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise ValueError("Result evidence must not contain symlinks")
        if path.is_file():
            with path.open("rb") as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
            files[str(path.relative_to(root))] = {"bytes": path.stat().st_size, "sha256": digest}
    return files


def command(arguments):
    return subprocess.run(
        ["xcrun", "xcresulttool", *arguments],
        check=True,
        capture_output=True,
        text=True,
        timeout=120,
    ).stdout


def collect(bundle, output, commit, run=command):
    if not re.fullmatch(r"[a-f0-9]{40}", commit):
        raise ValueError("Use the full source commit")
    bundle, output = bundle.resolve(), output.resolve()
    if output.is_relative_to(bundle):
        raise ValueError("Triage must remain outside the source result bundle")
    output.mkdir()  # Never replace earlier evidence, including interrupted exports.
    receipt = {
        "schema_version": 1,
        "commit": commit,
        "source_bundle": str(bundle),
        "status": "collecting",
        "complete_result_bundle": False,
        "omitted_videos": {},
    }

    def record():
        (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")

    record()
    if not bundle.exists():
        receipt["status"] = "result-unavailable"
        record()
        return receipt
    try:
        receipt["source_files"] = inventory(bundle)
        if not receipt["source_files"]:
            raise ValueError("Source result bundle is empty")
        summary = None
        for kind in ["summary", "tests"]:
            result = json.loads(run(["get", "test-results", kind, "--path", str(bundle)]))
            (output / f"{kind}.json").write_text(json.dumps(result, indent=2) + "\n")
            if kind == "summary":
                summary = result
        identifiers = sorted(
            {failure["testIdentifierString"] for failure in summary["testFailures"]}
        )
        receipt["failed_test_identifiers"] = identifiers
        for index, identifier in enumerate(identifiers):
            destination = output / f"failure-{index + 1:03d}"
            destination.mkdir()
            result = json.loads(
                run(
                    [
                        "get",
                        "test-results",
                        "activities",
                        "--path",
                        str(bundle),
                        "--test-id",
                        identifier,
                    ]
                )
            )
            (destination / "activities.json").write_text(json.dumps(result, indent=2) + "\n")
            with tempfile.TemporaryDirectory(prefix="reha-triage-") as temporary:
                exported = Path(temporary)
                run(
                    [
                        "export",
                        "attachments",
                        "--path",
                        str(bundle),
                        "--test-id",
                        identifier,
                        "--output-path",
                        str(exported),
                    ]
                )
                for name, identity in inventory(exported).items():
                    source = exported / name
                    if source.suffix.lower() in {".mp4", ".mov"}:
                        receipt["omitted_videos"][f"{destination.name}/{name}"] = identity
                        continue
                    target = destination / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(source, target)
        if inventory(bundle) != receipt["source_files"]:
            raise ValueError("Source result bundle changed while collecting evidence")
        receipt["status"] = "collected"
        receipt["files"] = {k: v for k, v in inventory(output).items() if k != "receipt.json"}
        record()
        return receipt
    except Exception:
        receipt["status"] = "collection-failed"
        record()
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--commit", required=True)
    args = parser.parse_args()
    receipt = collect(args.bundle, args.output, args.commit)
    print(json.dumps({"status": receipt["status"], "output": str(args.output)}))


if __name__ == "__main__":
    main()
