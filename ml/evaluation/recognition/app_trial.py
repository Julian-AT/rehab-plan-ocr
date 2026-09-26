"""Exercise baseline and frozen custom OCR through the app import/persistence route.

One public synthetic plan, two forced imports per model. No physical installation,
calendar access, real-photo accuracy claim or model promotion is performed.
"""

import argparse
import importlib.util
import json
import math
import platform
import shutil
import subprocess
import sys
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from ml.evaluation.conversation.native import run, sha, write  # noqa: E402
from ml.evaluation.device.simulator import BUNDLE, disposable, install  # noqa: E402

spec = importlib.util.spec_from_file_location(
    "ocr_assets", ROOT / "tooling/build/verify-native-assets.py"
)
assets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assets)


DEFAULT_CARD = "ocr-adaptation-smoke-002.json"


def registry_path(name, root=ROOT):
    if Path(name).name != name or Path(name).suffix != ".json":
        raise ValueError("Select one model card filename from ml/registry")
    path = root / "ml/registry" / name
    if path.is_symlink() or not path.is_file():
        raise ValueError("Select an existing regular model card in ml/registry")
    return path


def prepare_models(output, variant, root=ROOT, model_card=DEFAULT_CARD):
    if variant not in {"baseline", "frozen"}:
        raise ValueError("Only the corrected baseline and parity-passing frozen model are allowed")
    source = root / ".local/models/runtime/small"
    lock = json.loads((root / "ml/registry/runtime/small.lock.json").read_text())
    assets.model_bundle(source, lock, strict=True)
    manifest = json.loads((source / "manifest.json").read_text())
    replacement = None
    if variant == "frozen":
        card_path = registry_path(model_card, root)
        card = json.loads(card_path.read_text())
        selected = [row for row in card["variants"] if row["mode"] == "frozen-backbone"]
        if (
            len(selected) != 1
            or selected[0]["qualified"] is not False
            or selected[0]["parity"]["passed"] is not True
        ):
            raise ValueError("The frozen experimental recognizer must pass desktop parity")
        selected = selected[0]
        training = (root / selected["run"]).resolve()
        replacement = training / "deployment/recognizer.onnx"
        base = json.loads((root / "ml/registry/ocr-base.json").read_text())
        if (
            not training.is_relative_to((root / ".local/runs").resolve())
            or sha(training / "identity.json") != selected["run_identity_sha256"]
            or sha(replacement) != selected["onnx_sha256"]
            or base["deployment_dictionary_sha256"] != manifest["dictionary_sha256"]
        ):
            raise ValueError("Custom artifact, lineage or deployment dictionary changed")
        if model_card != DEFAULT_CARD:
            if card.get("promoted") is not False or card.get("physical_ios_verified") is not False:
                raise ValueError("Select an explicitly experimental model card")
            evidence = selected.get("evidence", {})
            for name in ["selection.json", "deployment/export.json", "deployment/parity.json"]:
                if evidence.get(name) != sha(training / name):
                    raise ValueError("Registered export evidence changed or is absent")
            selection = json.loads((training / "selection.json").read_text())
            parity = json.loads((training / "deployment/parity.json").read_text())
            export = json.loads((training / "deployment/export.json").read_text())
            if (
                selection["sha256"] != selected["checkpoint_sha256"]
                or sha(training / "selected.pdparams") != selection["sha256"]
                or parity.get("passed") is not True
                or parity.get("diagnostic", False) is not False
                or parity.get("graph_optimization", "GraphOptimizationLevel.ORT_ENABLE_ALL")
                != "GraphOptimizationLevel.ORT_ENABLE_ALL"
                or parity.get("artifact_sha256") != selected["onnx_sha256"]
                or parity.get("checkpoint_sha256") != selection["sha256"]
                or export.get("status") != "desktop-parity-passed"
                or export.get("run_identity_sha256") != selected["run_identity_sha256"]
                or export.get("selection_sha256") != evidence["selection.json"]
            ):
                raise ValueError("Registered checkpoint did not complete matching export parity")
        for entry in manifest["files"]:
            if entry["path"] == "rec-inference.onnx":
                entry.update(
                    sha256=selected["onnx_sha256"],
                    bytes=replacement.stat().st_size,
                    url="local-development:" + selected["onnx_sha256"],
                )
        # Keep the architecture/tier name: the app uses it to retain warm CPU
        # sessions. Variant identity lives in the exact manifest/artifact hashes.
        manifest["experimental"] = dict(
            qualified=False,
            registry_sha256=sha(card_path),
            run_identity_sha256=selected["run_identity_sha256"],
            baseline_manifest_sha256=sha(source / "manifest.json"),
        )
    output.mkdir(parents=True, exist_ok=False)
    for entry in manifest["files"]:
        name = entry["path"]
        shutil.copyfile(
            replacement if replacement and name == "rec-inference.onnx" else source / name,
            output / name,
        )
    shutil.copyfile(source / "dictionary.json", output / "dictionary.json")
    write(output / "manifest.json", manifest)
    assets.model_bundle(output, manifest, strict=True)
    return manifest


def complete(result, request, folder):
    if (
        result.get("run_id") != request["run_id"]
        or result.get("stage") != "passed"
        or result.get("variant") != request["variant"]
        or result.get("qualified") is not False
        or type(result.get("calendar_operations")) is not int
        or result["calendar_operations"] != 0
        or result.get("source_sha256") != request["source_sha256"]
        or result.get("model_manifest_sha256") != request["model_manifest_sha256"]
        or type(result.get("host_calls", {}).get("rejected_calendar_calls")) is not int
        or result["host_calls"]["rejected_calendar_calls"] != 0
        or type(result.get("host_calls", {}).get("native_reread_calls")) is not int
        or result["host_calls"]["native_reread_calls"] < 1
    ):
        raise ValueError("Recognition probe did not complete with the requested identities")
    cases = result.get("cases")
    if (
        not isinstance(cases, list)
        or not all(isinstance(c, dict) for c in cases)
        or [c.get("index") for c in cases] != [0, 1]
    ):
        raise ValueError("Both forced imports must complete in order")
    manifest = json.loads((folder / "models/manifest.json").read_text())
    if sha(folder / "models/manifest.json") != request["model_manifest_sha256"]:
        raise ValueError("Retained model manifest changed")
    ids = set()
    for index, row in enumerate(cases):
        seconds = row.get("import_seconds")
        if (
            row.get("duplicate") is not False
            or row.get("trace") != f"trace-{index}.json"
            or type(seconds) not in {int, float}
            or not math.isfinite(seconds)
            or seconds < 0
        ):
            raise ValueError("Cached, incomplete or invalid import observation")
        trace = json.loads((folder / row["trace"]).read_text())
        document = trace["document"]
        if (
            document["id"] != row["document_id"]
            or document["id"] in ids
            or document["source_hash"] != request["source_sha256"]
            # Historical field name: this is model-session reuse, not result reuse.
            or trace["cache_used"] is not (index == 1)
            or trace["model_manifest"] != manifest
            or trace["engine"] != manifest["engine"]
            or not any(
                s["name"] == "model_load" and s["status"] == "complete" for s in trace["stages"]
            )
            or not any(
                s["name"] == "recognition" and s["status"] in {"complete", "partial"}
                for s in trace["stages"]
            )
            or not any(
                s["name"] == "vision_refinement" and s["status"] == "complete"
                for s in trace["stages"]
            )
            or type(row["appointments"]) is not int
            or len(trace["appointments"]) != row["appointments"]
        ):
            raise ValueError("Persisted trace does not match this import")
        ids.add(document["id"])


def sources():
    names = run(
        [
            "git",
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "--",
            "apps/ios",
            "packages",
            "ml/registry/runtime",
            "config/toolchains",
            "tooling/build",
            "Cargo.toml",
            "Cargo.lock",
        ]
    )
    return {
        name: sha(ROOT / name)
        for name in sorted(set(names.splitlines()))
        if not name.endswith(".md")
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", required=True, type=Path)
    parser.add_argument("--simulator", required=True)
    parser.add_argument("--model-card", default=DEFAULT_CARD)
    args = parser.parse_args()
    output = args.run.resolve()
    if not output.is_relative_to(ROOT / ".local/runs"):
        raise ValueError("Use a new private run directory")
    device = disposable(args.simulator, run)
    card = registry_path(args.model_card)
    output.mkdir(parents=True, exist_ok=False)
    snapshot = sources()
    helpers = [
        Path(__file__),
        ROOT / "ml/evaluation/device/simulator.py",
        ROOT / "ml/evaluation/conversation/native.py",
        card,
    ]
    helper_hashes = {str(path.relative_to(ROOT)): sha(path) for path in helpers}
    report = dict(
        stage="building",
        qualified=False,
        physical_device=False,
        independent_synthetic_sources=1,
        source_revision=run(["git", "rev-parse", "HEAD"]),
        sources=snapshot,
        simulator=device,
        evaluator_sha256=sha(Path(__file__)),
        evaluation_sources=helper_hashes,
        host=platform.platform(),
        xcode=run(["xcodebuild", "-version"]),
        variants={},
    )
    write(output / "report.json", report)
    launched = False
    try:
        run(["make", "build", "TARGET=simulator"], log=output / "build.log")
        if snapshot != sources():
            raise ValueError("Sources changed during the app build")
        app = (
            ROOT / "apps/ios/build/DerivedData/Build/Products/Debug-iphonesimulator/Laßnitzhöhe.app"
        )
        report["app_binary_sha256"] = sha(app / "Termine.debug.dylib")
        container = install(app, args.simulator, run)
        folder = container / "Documents/recognition-probe"
        folder.mkdir(exist_ok=True)
        for variant in ["baseline", "frozen"]:
            destination = output / variant
            destination.mkdir()
            manifest = prepare_models(destination / "models", variant, model_card=args.model_card)
            shutil.copytree(destination / "models", folder / "models", dirs_exist_ok=True)
            source = ROOT / "ml/evaluation/fixtures/synthetic-day.png"
            shutil.copyfile(source, folder / "input.png")
            request = dict(
                run_id=str(uuid.uuid4()),
                variant=variant,
                source_sha256=sha(source),
                model_manifest_sha256=sha(destination / "models/manifest.json"),
            )
            write(destination / "input.json", request)
            write(folder / "input.json", request)
            report["stage"] = variant
            write(output / "report.json", report)
            run(
                [
                    "xcrun",
                    "simctl",
                    "launch",
                    "--terminate-running-process",
                    args.simulator,
                    BUNDLE,
                    "--recognition-provider-probe",
                    request["run_id"],
                ],
                log=destination / "launch.log",
            )
            launched = True
            deadline = time.monotonic() + 300
            result = {}
            while time.monotonic() < deadline:
                try:
                    value = json.loads((folder / "result.json").read_text())
                    if value.get("run_id") == request["run_id"]:
                        result = value
                        if result.get("stage") in {"passed", "failed"}:
                            break
                except (OSError, ValueError):
                    pass
                time.sleep(0.5)
            write(destination / "result.json", result)
            for index in range(2):
                path = folder / f"trace-{index}.json"
                if path.exists():
                    shutil.copyfile(path, destination / path.name)
            complete(result, request, destination)
            run(["xcrun", "simctl", "terminate", args.simulator, BUNDLE])
            launched = False
            observations = []
            for row in result["cases"]:
                trace = json.loads((destination / row["trace"]).read_text())
                observations.append(
                    dict(
                        row,
                        model_session_reused=trace["cache_used"],
                        stages=trace["stages"],
                        trace_sha256=sha(destination / row["trace"]),
                    )
                )
            report["variants"][variant] = dict(
                result_sha256=sha(destination / "result.json"),
                manifest=manifest,
                cases=observations,
                host_calls=result["host_calls"],
            )
            print(f"{variant}: two uncached app imports and persisted traces passed", flush=True)
        if snapshot != sources():
            raise ValueError("Sources changed during evaluation")
        if helper_hashes != {str(path.relative_to(ROOT)): sha(path) for path in helpers}:
            raise ValueError("Evaluation helpers changed during evaluation")
        report["stage"] = "compatibility_passed"
    except Exception as error:
        report.update(stage="failed", error=str(error))
        raise
    finally:
        if launched:
            try:
                run(["xcrun", "simctl", "terminate", args.simulator, BUNDLE], timeout=30)
            except (OSError, subprocess.SubprocessError) as error:
                report["cleanup_warning"] = str(error)
        write(output / "report.json", report)


if __name__ == "__main__":
    main()
