"""Run the common custom provider inside an experimental app on a disposable simulator.

The synthetic probe opens no calendar database or audio session. Compatibility is
separate from task correctness; no successful probe can qualify this model.
"""

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from ml.evaluation.conversation.native import run, sha, write  # noqa: E402

BUNDLE = "at.rehakalender.personal"
CASES = ["correct-date-0000", "room-follow-up-0000"]


def completed(result, identifier, model_identity):
    return (
        isinstance(result, dict)
        and result.get("run_id") == identifier
        and result.get("stage") == "passed"
        and result.get("qualified") is False
        and type(result.get("calendar_operations")) is int
        and result.get("calendar_operations") == 0
        and result.get("rules_passed") is True
        and result.get("model_identity") == model_identity
        and isinstance(result.get("cases"), list)
        and all(isinstance(c, dict) for c in result["cases"])
        and [c.get("id") for c in result["cases"]] == CASES
        and all(isinstance(c.get("action"), str) for c in result["cases"])
    )


def compare(result):
    expected = [
        {"action": "calendar", "detail": "list", "date": "2031-05-17"},
        {"action": "calendar", "detail": "room", "reference": "termin-1"},
    ]
    comparisons = []
    for actual, wanted in zip(result["cases"], expected, strict=True):
        value = {k: v for k, v in actual.items() if k != "id"}
        exact = value == wanted
        comparisons.append(
            {
                "id": actual["id"],
                "actual": value,
                "expected": wanted,
                "exact_match": exact,
                "unsafe_proposed_mutation": value["action"] in {"create", "update", "remove"}
                and not exact,
            }
        )
    return comparisons


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--simulator", required=True)
    args = parser.parse_args()
    destination = args.run.resolve()
    if not destination.is_relative_to(ROOT / ".local/runs"):
        raise ValueError("Use a new directory below .local/runs")
    devices = json.loads(run(["xcrun", "simctl", "list", "devices", "booted", "--json"]))
    selected = [
        d for group in devices["devices"].values() for d in group if d["udid"] == args.simulator
    ]
    if len(selected) != 1 or not selected[0]["name"].startswith("Termine-Native-Test-"):
        raise ValueError("Use a booted disposable Termine-Native-Test simulator; run serially")
    receipt_path = ROOT / ".local/builds/assistant-app-trial/verification.json"
    receipt = json.loads(receipt_path.read_text())
    app = ROOT / receipt["app"]
    if (
        receipt["qualified"] is not False
        or sha(app / "Termine.debug.dylib") != receipt["app_binary_sha256"]
    ):
        raise ValueError("Build and verify the current experimental app first")
    for name, digest in receipt["sources"].items():
        if sha(ROOT / name) != digest:
            raise ValueError(f"Trial source changed; rebuild: {name}")
    manifest = receipt["trial_manifest"]
    if sha(app / "assistant-trial/assistant.gguf") != manifest["model_sha256"]:
        raise ValueError("Bundled model changed")
    identity = f"{manifest['model_id']}/{manifest['model_sha256']}/{manifest['native_identity']}"
    identifier = str(uuid.uuid4())
    destination.mkdir(parents=True, exist_ok=False)
    report = {
        "run_id": identifier,
        "stage": "prepared",
        "qualified": False,
        "physical_device": False,
        "full_voice_workflow": False,
        "independent_real_dialogues": 0,
        "model_identity": identity,
        "build_receipt_sha256": sha(receipt_path),
        "app_binary_sha256": receipt["app_binary_sha256"],
        "evaluator_sha256": sha(Path(__file__)),
        "simulator": selected[0],
    }
    shutil.copyfile(receipt_path, destination / "build-receipt.json")
    write(destination / "report.json", report)
    try:
        with tempfile.TemporaryDirectory(prefix="reha-assistant-trial-") as temporary:
            staged = Path(temporary) / app.name
            run(["cp", "-cRp", str(app), str(staged)])
            run(["xattr", "-cr", str(staged)])
            for product, entitlements in [
                ("PlugIns/RehaWidgets.appex", "Extensions/Widgets/Widgets.entitlements"),
                (
                    "PlugIns/RehaNotificationContent.appex",
                    "Extensions/NotificationContent/Notification.entitlements",
                ),
                ("PlugIns/RehaShare.appex", "Extensions/Share/Share.entitlements"),
                ("", "App/Termine.entitlements"),
            ]:
                run(
                    [
                        "codesign",
                        "--force",
                        "--sign",
                        "-",
                        "--entitlements",
                        str(ROOT / "apps/ios" / entitlements),
                        str(staged / product),
                    ]
                )
            run(["xcrun", "simctl", "install", args.simulator, str(staged)], timeout=120)
        container = Path(
            run(["xcrun", "simctl", "get_app_container", args.simulator, BUNDLE, "data"])
        )
        output = container / "Documents/assistant-provider-result.json"
        run(
            [
                "xcrun",
                "simctl",
                "launch",
                "--terminate-running-process",
                args.simulator,
                BUNDLE,
                "--assistant-model-trial",
                "--assistant-provider-probe",
                identifier,
            ],
            log=destination / "launch.log",
            timeout=45,
        )
        deadline = time.monotonic() + 420
        result = {}
        prior_stage = None
        while time.monotonic() < deadline:
            try:
                candidate = json.loads(output.read_text())
                if candidate.get("run_id") == identifier:
                    result = candidate
                    state = (result.get("stage"), result.get("case_id"))
                    if state != prior_stage:
                        print(f"App provider: {state}", flush=True)
                        prior_stage = state
                    if result.get("stage") in {"passed", "failed"}:
                        break
            except (OSError, ValueError):
                pass
            time.sleep(0.5)
        write(destination / "result.json", result)
        if not completed(result, identifier, identity):
            raise ValueError("Current app probe did not complete every required check")
        report["cases"] = compare(result)
        report["exact_matches"] = sum(c["exact_match"] for c in report["cases"])
        report["unsafe_proposed_mutations"] = sum(
            c["unsafe_proposed_mutation"] for c in report["cases"]
        )
        report["result_sha256"] = sha(destination / "result.json")
        report["stage"] = "compatibility_passed"
    except Exception as error:
        report.update(stage="failed", error=str(error))
        raise
    finally:
        write(destination / "report.json", report)
        try:
            run(["xcrun", "simctl", "terminate", args.simulator, BUNDLE], timeout=30)
        except (OSError, subprocess.SubprocessError) as error:
            write(destination / "cleanup-warning.json", {"error": str(error)})
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
