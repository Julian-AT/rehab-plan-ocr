"""Exercise the actual experimental Apple assistant library with verified GGUF assets.

Synthetic development prompts only. Host and simulator results are compatibility
evidence, not physical-device performance or production model qualification.
"""

import argparse
import ast
import hashlib
import importlib.util
import json
import subprocess
import sys
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PACKAGE = ROOT / "packages/apple/LocalAssistant"
FRAMEWORK = PACKAGE / "RehaAssistantNative.xcframework"
BUNDLE = "at.rehakalender.tests.assistant"
sys.path.insert(0, str(ROOT))
from ml.evaluation.conversation.intent import InvalidIntent, parse  # noqa: E402

spec = importlib.util.spec_from_file_location(
    "native_assembly", ROOT / "tooling/build/assemble-native.py"
)
assembly = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assembly)


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write(path, data):
    temporary = path.with_suffix(path.suffix + ".part")
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(path)


def run(command, *, log=None, timeout=900):
    if log:
        with log.open("w") as output:
            subprocess.run(
                command,
                cwd=ROOT,
                check=True,
                stdout=output,
                stderr=subprocess.STDOUT,
                timeout=timeout,
            )
        return None
    return subprocess.check_output(command, cwd=ROOT, text=True, timeout=timeout).strip()


def library(variant):
    receipt_path = FRAMEWORK.resolve().parent / "receipt.json"
    receipt = json.loads(receipt_path.read_text())
    record = receipt["identity"][variant]
    identity = record["identity"]
    paths = {
        str(p.relative_to(PACKAGE)): sha(p)
        for p in sorted((PACKAGE / "Native").rglob("*"))
        if p.is_file()
    }
    if (
        identity["sources"] != paths
        or identity["builder_sha256"] != sha(ROOT / "tooling/build/build-assistant-native.py")
        or identity["cache_helper_sha256"] != sha(ROOT / "tooling/build/assemble-native.py")
        or identity["source_revision"]
        != json.loads((ROOT / "ml/registry/assistant-base.json").read_text())["converter_revision"]
    ):
        raise ValueError("Native library source changed; rebuild the assistant runtime")
    path = ROOT / ".local/builds/assistant-native/libraries" / assembly.key(identity)
    if not assembly.matches(path, identity, {"libRehaAssistantNative.a"}):
        raise ValueError("Native assistant library artifact changed")
    if not assembly.matches(
        receipt_path.parent, receipt["identity"], {"RehaAssistantNative.xcframework/Info.plist"}
    ):
        raise ValueError("Assistant XCFramework artifact changed")
    return path, record


def completed(path, request):
    try:
        result = json.loads(path.read_text())
        return (
            bool(request["cases"])
            and result["run_id"] == request["runID"]
            and result["model_sha256"] == request["model"]["sha256"]
            and result["stage"] == "passed"
            and result["qualified"] is False
            and [c["id"] for c in result["cases"]] == [c["id"] for c in request["cases"]]
            and all(type(c["output"]) is str and c["output"] for c in result["cases"])
            and all(
                result.get(name) is True
                for name in [
                    "cancellation_passed",
                    "deadline_passed",
                    "context_limit_passed",
                    "output_limit_passed",
                    "state_isolation_passed",
                ]
            )
        )
    except (OSError, ValueError, KeyError, TypeError):
        return False


def host(destination, request):
    native, identity = library("host")
    common = [
        "xcrun",
        "swiftc",
        "-swift-version",
        "6",
        "-strict-concurrency=complete",
        "-warnings-as-errors",
        "-parse-as-library",
        "-I",
        str(native / "Headers"),
        "-L",
        str(native),
        "-lRehaAssistantNative",
        "-framework",
        "Accelerate",
        "-lc++",
        str(PACKAGE / "Sources/LocalAssistant/LocalAssistant.swift"),
    ]
    for source, output in [("BoundaryTests", "boundary-tests"), ("RuntimeProbe", "runtime-probe")]:
        run(
            [
                *common,
                str(PACKAGE / "Tests" / (source + ".swift")),
                "-o",
                str(destination / output),
            ],
            log=destination / (output + "-build.log"),
        )
    run([str(destination / "boundary-tests")], log=destination / "boundary-tests.log")
    result = destination / "host-result.json"
    run(
        [str(destination / "runtime-probe"), str(destination / "input.json"), str(result)],
        log=destination / "host-runtime.log",
    )
    if not completed(result, request):
        raise ValueError("Native host probe did not complete all required checks")
    return {
        "library": identity,
        "result_sha256": sha(result),
        "binary_sha256": sha(destination / "runtime-probe"),
    }


def simulator(destination, request, identifier):
    _, identity = library("simulator")
    devices = json.loads(run(["xcrun", "simctl", "list", "devices", "booted", "--json"]))
    chosen = [d for group in devices["devices"].values() for d in group if d["udid"] == identifier]
    if len(chosen) != 1 or not chosen[0]["name"].startswith("Termine-Native-Test-"):
        raise ValueError("Use one booted disposable Termine-Native-Test simulator; run serially")
    project = {
        "name": "AssistantRuntimeProbe",
        "options": {"deploymentTarget": {"iOS": "26.0"}},
        "packages": {"LocalAssistant": {"path": str(PACKAGE)}},
        "targets": {
            "AssistantRuntimeProbe": {
                "type": "application",
                "platform": "iOS",
                "sources": [
                    str(PACKAGE / "Tests/RuntimeProbe.swift"),
                    {"path": str(destination / "input.json"), "buildPhase": "resources"},
                    {"path": request["model"]["path"], "buildPhase": "resources"},
                ],
                "dependencies": [{"package": "LocalAssistant"}],
                "settings": {
                    "base": {
                        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE,
                        "GENERATE_INFOPLIST_FILE": "YES",
                        "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
                        "SWIFT_VERSION": "6.0",
                        "CODE_SIGNING_ALLOWED": "NO",
                    }
                },
            }
        },
    }
    write(destination / "project.json", project)
    run(
        [
            "xcodegen",
            "generate",
            "--spec",
            str(destination / "project.json"),
            "--project",
            str(destination),
        ],
        log=destination / "project.log",
    )
    run(
        [
            "xcodebuild",
            "-project",
            str(destination / "AssistantRuntimeProbe.xcodeproj"),
            "-scheme",
            "AssistantRuntimeProbe",
            "-sdk",
            "iphonesimulator",
            "-destination",
            "generic/platform=iOS Simulator",
            "-derivedDataPath",
            str(destination / "build"),
            "CODE_SIGNING_ALLOWED=NO",
            "ARCHS=arm64",
            "build",
        ],
        log=destination / "simulator-build.log",
    )
    app = destination / "build/Build/Products/Debug-iphonesimulator/AssistantRuntimeProbe.app"
    if sha(app / "assistant.gguf") != request["model"]["sha256"]:
        raise ValueError("Bundled evaluation model differs from the selected artifact")
    run(["xcrun", "simctl", "install", identifier, str(app)], timeout=120)
    container = Path(run(["xcrun", "simctl", "get_app_container", identifier, BUNDLE, "data"]))
    output = container / "Documents/assistant-result.json"
    run(
        ["xcrun", "simctl", "launch", "--terminate-running-process", identifier, BUNDLE], timeout=45
    )
    try:
        deadline = time.monotonic() + 900
        previous_stage = None
        while time.monotonic() < deadline:
            try:
                progress = json.loads(output.read_text())
                if progress.get("run_id") == request["runID"]:
                    stage = progress.get("stage")
                    if stage != previous_stage:
                        print(f"Assistant simulator: {stage}", flush=True)
                        previous_stage = stage
                    if stage in {"failed", "passed"}:
                        break
            except (OSError, ValueError):
                pass
            time.sleep(0.5)
        if output.is_file():
            (destination / "simulator-result.json").write_bytes(output.read_bytes())
        if not completed(output, request):
            raise ValueError("Native simulator probe did not complete all required checks")
        return {
            "library": identity,
            "device": chosen[0],
            "result_sha256": sha(output),
            "app_binary_sha256": sha(app / "AssistantRuntimeProbe"),
        }
    finally:
        try:
            run(["xcrun", "simctl", "terminate", identifier, BUNDLE], timeout=30)
        except (subprocess.SubprocessError, OSError) as error:
            write(destination / "simulator-cleanup-warning.json", {"error": str(error)})


def prepared_cases(model, registry, parity):
    """Match saved prompts against the exact training data and pinned prompt source."""
    source_run = model.parent.parent
    identity_path = source_run / "identity.json"
    identity = json.loads(identity_path.read_text())
    settings_path = source_run / "settings.json"
    if (
        sha(identity_path) != registry["run_identity_sha256"]
        or sha(settings_path) != identity["settings_sha256"]
    ):
        raise ValueError("Development run identity changed")
    dataset_path = Path(json.loads(settings_path.read_text())["dataset"])
    contract = ROOT / "ml/training/assistant/contract.py"
    if (
        sha(dataset_path) != registry["dataset_sha256"]
        or sha(contract) != identity["lineage"]["sources_sha256"][str(contract.relative_to(ROOT))]
    ):
        raise ValueError("Dataset or recorded prompt source changed")
    system = next(
        ast.literal_eval(node.value)
        for node in ast.parse(contract.read_text()).body
        if isinstance(node, ast.Assign)
        and any(isinstance(t, ast.Name) and t.id == "SYSTEM" for t in node.targets)
    )
    rows = [
        r for r in json.loads(dataset_path.read_text())["samples"] if r["partition"] == "validation"
    ]
    cases = []
    for index, (row, comparison) in enumerate(zip(rows[: len(parity)], parity, strict=True)):
        prompt = (model.parent / f"case-{index:04}.prompt.txt").read_text()
        expected = (
            "<|im_start|>system\n"
            + system
            + "<|im_end|>\n<|im_start|>user\n"
            + json.dumps(row["context"], ensure_ascii=False, sort_keys=True)
            + "\n"
            + row["utterance"]
            + "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
        )
        if (
            prompt != expected
            or row["id"] != comparison["id"]
            or row["expected"] != comparison["expected"]
        ):
            raise ValueError("Saved deployment prompt differs from its verified development case")
        cases.append(
            {"id": row["id"], "prompt": prompt, "references": row["context"]["visible_references"]}
        )
    return cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--simulator")
    parser.add_argument("--cases", type=int, default=2)
    args = parser.parse_args()
    destination = args.run.resolve()
    if not destination.is_relative_to(ROOT / ".local/runs") or not 1 <= args.cases <= 40:
        raise ValueError("Use a new .local/runs directory and 1–40 development cases")
    registry_path = ROOT / "ml/registry/assistant-development-001.json"
    registry = json.loads(registry_path.read_text())
    model = ROOT / registry["artifact"]["path"]
    if (
        sha(model) != registry["artifact"]["sha256"]
        or model.stat().st_size != registry["artifact"]["bytes"]
    ):
        raise ValueError("Experimental model no longer matches its recorded export")
    parity_path = model.parent / "parity.json"
    if sha(parity_path) != registry["deployment_complete_answer_parity"]["report_sha256"]:
        raise ValueError("Development comparison report changed")
    parity = json.loads(parity_path.read_text())["cases"][: args.cases]
    request = {
        "runID": str(uuid.uuid4()),
        "model": {"path": str(model), "sha256": sha(model), "bytes": model.stat().st_size},
        "cases": prepared_cases(model, registry, parity),
    }
    destination.mkdir(parents=True, exist_ok=False)
    write(destination / "input.json", request)
    report = {
        "status": "running",
        "qualified": False,
        "physical_device": False,
        "independent_real_dialogues": 0,
        "source_revision": run(["git", "rev-parse", "HEAD"]),
        "registry_sha256": sha(registry_path),
        "input_sha256": sha(destination / "input.json"),
        "sources": {
            str(p.relative_to(ROOT)): sha(p)
            for p in [
                Path(__file__),
                PACKAGE / "Tests/RuntimeProbe.swift",
                PACKAGE / "Tests/BoundaryTests.swift",
                PACKAGE / "Sources/LocalAssistant/LocalAssistant.swift",
                PACKAGE / "Package.swift",
            ]
        },
        "host_os": run(["sw_vers", "-productVersion"]),
        "xcode": run(["xcodebuild", "-version"]),
    }
    write(destination / "report.json", report)
    try:
        report["host"] = host(destination, request)
        write(destination / "report.json", report)
        if args.simulator:
            report["simulator"] = simulator(destination, request, args.simulator)
        report["cases"] = []
        for provider in ["host", "simulator"]:
            path = destination / f"{provider}-result.json"
            if not path.exists():
                continue
            outputs = json.loads(path.read_text())["cases"]
            for original, generated, prepared in zip(
                parity, outputs, request["cases"], strict=True
            ):
                case = {
                    "provider": provider,
                    "id": original["id"],
                    "family": original["family"],
                    "exact_match": False,
                    "unsafe_mutation": False,
                    "complete_answer_equals_desktop_GGUF": generated["output"].strip()
                    == original["outputs"]["assistant"]
                    .strip()
                    .removesuffix("[end of text]")
                    .rstrip(),
                }
                try:
                    actual = parse(generated["output"], references=prepared["references"])
                    case.update(
                        schema_valid=True, exact_match=actual == original["expected"], actual=actual
                    )
                    case["unsafe_mutation"] = (
                        actual["action"] in {"create", "update", "remove"}
                        and not case["exact_match"]
                    )
                except InvalidIntent as error:
                    case.update(schema_valid=False, rejection=str(error))
                report["cases"].append(case)
        report["status"] = "completed-experimental-only"
    except BaseException as error:
        report.update(status="failed", error=str(error))
        raise
    finally:
        write(destination / "report.json", report)
    print(
        json.dumps(
            {"status": report["status"], "cases": report["cases"]}, ensure_ascii=False, indent=2
        )
    )


if __name__ == "__main__":
    main()
