"""Require the recorded UI-test runtime before creating or reusing a simulator."""

import argparse
import hashlib
import json
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "config/testing/simulator.json"


def select(profile, inventory, simulator=None):
    runtime = next(
        (r for r in inventory["runtimes"] if r["identifier"] == profile["runtime"]), None
    )
    if (
        runtime is None
        or not runtime.get("isAvailable")
        or runtime["version"] != profile["version"]
        or runtime["buildversion"] != profile["build"]
    ):
        raise ValueError(
            f"Required simulator runtime {profile['runtime']} / {profile['build']} is unavailable; "
            "no newer runtime will be substituted"
        )
    device = None
    if simulator:
        device = next(
            (d for d in inventory["devices"].get(profile["runtime"], []) if d["udid"] == simulator),
            None,
        )
        if (
            device is None
            or not device.get("isAvailable")
            or not device["name"].startswith("Termine-Native-Test-")
            or device.get("deviceTypeIdentifier")
            != "com.apple.CoreSimulator.SimDeviceType.iPhone-17"
        ):
            raise ValueError(
                "Reuse requires an owned iPhone 17 test simulator on the pinned runtime"
            )
    return {
        "runtime": {k: runtime[k] for k in ["identifier", "version", "buildversion"]},
        "reused_device": device,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=["local", "ci"], default="local")
    parser.add_argument("--simulator")
    args = parser.parse_args()
    config = CONFIG.read_bytes()
    inventory = json.loads(
        subprocess.check_output(["xcrun", "simctl", "list", "--json"], text=True, timeout=30)
    )
    result = select(json.loads(config)[args.profile], inventory, args.simulator)
    result.update(profile=args.profile, config_sha256=hashlib.sha256(config).hexdigest())
    output = ROOT / "apps/ios/build" / f"simulator-environment-{time.time_ns()}.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x") as stream:
        stream.write(json.dumps(result, indent=2) + "\n")
    print(result["runtime"]["identifier"])


if __name__ == "__main__":
    main()
