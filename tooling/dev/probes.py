"""Run the retained standalone Apple experiments through explicit, private entry points."""

import argparse
import hashlib
import json
import os
import platform
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROBES = {
    "document": ["ml/experiments/apple-document/DocumentProbe.swift"],
    "speech-availability": ["ml/evaluation/speech/SpeechFileProbe.swift"],
    "voice-rules": [
        "apps/ios/Features/Conversation/VoiceRules.swift",
        "ml/experiments/voice-rules/RulesBenchmark.swift",
    ],
}


def run(probe, output, *, mode="text", image=None):
    if platform.system() != "Darwin":
        raise ValueError("Apple probes require macOS 26 and the pinned Xcode toolchain")
    output = output.resolve()
    if not output.is_relative_to(ROOT / ".local/runs"):
        raise ValueError("Probe evidence belongs below .local/runs")
    if probe == "document" and (image is None or not image.is_file()):
        raise ValueError("The document probe requires an existing input image")
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    compiler = subprocess.check_output(["xcrun", "swiftc", "--version"], text=True).strip()
    sources = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in PROBES[probe]}
    sources["tooling/dev/probes.py"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    identity = hashlib.sha256(json.dumps([compiler, sources], sort_keys=True).encode()).hexdigest()
    build = ROOT / ".local/builds/probes" / probe / identity
    build.mkdir(parents=True, exist_ok=True)
    executable = build / "probe"
    command = [
        "xcrun",
        "swiftc",
        "-swift-version",
        "6",
        "-strict-concurrency=complete",
        "-parse-as-library",
        "-target",
        f"{platform.machine()}-apple-macosx26.0",
        "-O",
        "-module-cache-path",
        str(build / "modules"),
        *[str(ROOT / p) for p in PROBES[probe]],
        "-o",
        str(executable),
    ]
    receipt = {
        "schema_version": 1,
        "probe": probe,
        "compiler": compiler,
        "system": platform.platform(),
        "sources": sources,
        "qualified": False,
        "physical_iphone_measurement": False,
        "command": command,
        "status": "started",
    }
    try:
        with (output / "build.log").open("w") as log:
            subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        receipt["binary_sha256"] = hashlib.sha256(executable.read_bytes()).hexdigest()
        arguments = [str(executable)]
        if probe == "speech-availability":
            arguments.append("--inventory")
        if probe == "document":
            receipt["input_sha256"] = hashlib.sha256(image.read_bytes()).hexdigest()
            arguments.extend([mode, str(image.resolve()), str(output / "document.json")])
        with (
            (output / "result.json").open("w") as result,
            (output / "runtime.log").open("w") as log,
        ):
            subprocess.run(arguments, cwd=ROOT, stdout=result, stderr=log, timeout=120, check=True)
        json.loads((output / "result.json").read_text())
        receipt["status"] = "executed-not-qualified"
    except BaseException as error:
        receipt.update(status="failed", error_type=type(error).__name__)
        raise
    finally:
        (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("probe", choices=PROBES)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--mode", choices=["text", "documents"], default="text")
    parser.add_argument("--input", type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    run(args.probe, args.run, mode=args.mode, image=args.input)


if __name__ == "__main__":
    main()
