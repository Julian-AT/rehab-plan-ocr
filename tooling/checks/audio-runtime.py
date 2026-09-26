"""Isolate real AVAudioEngine startup from app/models on a disposable simulator."""

import argparse
import hashlib
import json
import platform
import shutil
import subprocess
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = "at.rehakalender.tests.audioengine"


def command(*args, timeout=120, stdout=subprocess.PIPE):
    return subprocess.run(
        args, check=True, text=True, stdout=stdout, stderr=subprocess.STDOUT, timeout=timeout
    )


def completed(path, identifier):
    if not path.is_file():
        return False
    try:
        value = json.loads(path.read_text())
        return value.get("run_id") == identifier and value.get("stage") == "passed"
    except (ValueError, OSError):
        return False


def verify(output, simulator=None, attempts=3):
    output = output.resolve()
    if not output.is_relative_to(ROOT / ".local/runs") or output.exists():
        raise ValueError("Use a new run directory under .local/runs")
    if not 1 <= attempts <= 10:
        raise ValueError("Use between one and ten attempts")
    devices = json.loads(command("xcrun", "simctl", "list", "devices", "--json").stdout)
    all_devices = [d for group in devices["devices"].values() for d in group]
    if any(d["state"] == "Booted" and d["udid"] != simulator for d in all_devices):
        raise ValueError("Run audio verification serially; another simulator is booted")
    if simulator and not any(
        d["udid"] == simulator
        and d["state"] == "Booted"
        and d["name"].startswith(("Termine-Native-Test-", "Reha-Audio-Test-"))
        for d in all_devices
    ):
        raise ValueError("Only a booted disposable test simulator can be reused")
    output.mkdir(parents=True)
    source = ROOT / "apps/ios/Tests/AudioRuntime"
    report = {
        "passed": False,
        "attempts": [],
        "host": platform.platform(),
        "source_sha256": hashlib.sha256((source / "Probe.swift").read_bytes()).hexdigest(),
        "xcode": command("xcodebuild", "-version").stdout.strip(),
        "sdk": command("xcrun", "--sdk", "iphonesimulator", "--show-sdk-version").stdout.strip(),
    }
    owned = simulator is None
    try:
        shutil.copy2(source / "Probe.swift", output / "Probe.swift")
        shutil.copy2(source / "project.yml", output / "project.yml")
        with (output / "build.log").open("w") as log:
            command(
                "xcodegen",
                "generate",
                "--spec",
                str(output / "project.yml"),
                "--project",
                str(output),
                stdout=log,
            )
            command(
                "xcodebuild",
                "-project",
                str(output / "AudioEngineProbe.xcodeproj"),
                "-scheme",
                "AudioEngineProbe",
                "-configuration",
                "Debug",
                "-sdk",
                "iphonesimulator",
                "-destination",
                "generic/platform=iOS Simulator",
                "-derivedDataPath",
                str(output / "build"),
                "CODE_SIGNING_ALLOWED=NO",
                "build",
                timeout=300,
                stdout=log,
            )
        if owned:
            simulator = command(
                "xcrun",
                "simctl",
                "create",
                f"Reha-Audio-Test-{uuid.uuid4()}",
                "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
            ).stdout.strip()
            command("xcrun", "simctl", "boot", simulator)
            command("xcrun", "simctl", "bootstatus", simulator, "-b")
        report["simulator"] = simulator
        (output / "devices.json").write_text(
            command("xcrun", "simctl", "list", "devices", "--json").stdout
        )
        app = output / "build/Build/Products/Debug-iphonesimulator/AudioEngineProbe.app"
        command("xcrun", "simctl", "install", simulator, str(app))
        container = Path(
            command(
                "xcrun", "simctl", "get_app_container", simulator, BUNDLE, "data"
            ).stdout.strip()
        )
        stage = container / "Documents/audio-probe.json"
        for index in range(attempts):
            identifier = str(uuid.uuid4())
            stage.unlink(missing_ok=True)
            entry = {"run_id": identifier, "passed": False}
            report["attempts"].append(entry)
            start = time.monotonic()
            try:
                with (output / f"attempt-{index + 1}.log").open("w") as log:
                    command(
                        "xcrun",
                        "simctl",
                        "launch",
                        "--terminate-running-process",
                        "--console",
                        simulator,
                        BUNDLE,
                        identifier,
                        timeout=45,
                        stdout=log,
                    )
                entry["passed"] = completed(stage, identifier)
            finally:
                entry["elapsed_seconds"] = time.monotonic() - start
                if stage.is_file():
                    shutil.copy2(stage, output / f"attempt-{index + 1}.json")
            # simctl can return zero after the child crashes. Require its fresh
            # render-time assertion and final success record, not the launch code.
            if not entry["passed"]:
                raise RuntimeError(
                    "Audio engine did not complete; inspect attempt log/stage and crash reports"
                )
        report["passed"] = True
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
        raise
    finally:
        (output / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
        cleanup = [["terminate", simulator, BUNDLE]] if simulator else []
        if simulator and owned:
            cleanup += [["shutdown", simulator], ["delete", simulator]]
        for operation in cleanup:
            try:
                subprocess.run(
                    ["xcrun", "simctl", *operation],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=30,
                )
            except (OSError, subprocess.SubprocessError) as error:
                report.setdefault("cleanup_warnings", []).append(str(error))
        (output / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"attempts": len(report["attempts"]), "passed": report["passed"]}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--simulator")
    parser.add_argument("--attempts", type=int, default=3)
    args = parser.parse_args()
    verify(args.run, args.simulator, args.attempts)
