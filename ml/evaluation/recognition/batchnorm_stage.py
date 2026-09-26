"""Predeclared full-graph BatchNorm division on twelve immutable development cases."""

import argparse
import gc
import importlib.metadata
import json
import os
import sys
from pathlib import Path

from batchnorm_graph import lower_batchnorm
from batchnorm_onnx import LEVELS, session
from batchnorm_reciprocal import machine
from batchnorm_replay import validate_attributes
from convolution_lowering import ROOT, digest, unchanged, write
from convolution_stage import lower_model
from operation_parity import attributes, instrument_pir

PREVIOUS = ROOT / ".local/runs/ocr-batchnorm-onnx-20260926-s19-001"
REPORT = "0eab7dc07d992242db255bf3faeb1889d01135ef8efbc75f69400c7c41cdea25"
SELECTION = ROOT / ".local/runs/ocr-convolution-stage-20260926-s18-001/protocol.json"
SELECTION_SHA = "c11b79035e610c11260d46c52b973f60ea611ab8ce55a867feb54aa0f311add0"
VARIANTS = ["division", "division-convolution"]
RULE = {
    "selection": "Reuse all twelve original convolution-stage cases and their fixed order.",
    "variants": VARIANTS,
    "transform": "All 58 FP32 NCHW inference BatchNorms: unchanged epsilon/parameters, Paddle grouping, Div.",
    "convolution": "Second variant additionally reuses the two already tested 2x2 Conv lowerings.",
    "levels": LEVELS,
    "runtime": "CPUExecutionProvider, 2 intra-op / 1 inter-op threads, pinned native ARM64 host.",
    "controls": "First reproduce every deployed original against dynamic Paddle; stop on any disagreement.",
    "reload": "Every serialized optimized variant must reproduce every candidate output byte-for-byte.",
    "rtol": 1e-3,
    "atol": 1e-5,
    "same_ctc_tokens": True,
    "candidate_failure": "Retain and complete all twelve cases; do not tune this experiment.",
    "selection_priority": VARIANTS,
    "gate": "All twelve original controls and cases at both levels; prefer fewer graph changes.",
    "qualified": False,
    "full_corpus_automatic": False,
}


def decision(rows, runs):
    """No partial, duplicated or reordered evidence can qualify a graph variant."""
    required = [(run["role"], case["id"], case["width"]) for run in runs for case in run["cases"]]
    actual = [(row["role"], row["id"], row["width"]) for row in rows]
    complete = len(required) == 12 and len(set(required)) == 12 and actual == required
    controls = complete and all(row["original_control_reproduced"] for row in rows)
    passed = {
        name: controls
        and all(
            row["variants"].get(name + "-" + level, {}).get("allclose") is True
            and row["variants"][name + "-" + level].get("same_tokens") is True
            and row["variants"][name + "-" + level].get("reload_bitwise_equal") is True
            for row in rows
            for level in LEVELS
        )
        for name in VARIANTS
    }
    return {
        "controls_valid": controls,
        "variant_passed": passed,
        "selected_for_full_corpus": next((name for name in VARIANTS if passed[name]), None),
        "qualified": False,
    }


def native_attributes(original, path):
    import onnx

    nodes = {
        node.output[0]: node for node in original.graph.node if node.op_type == "BatchNormalization"
    }
    if len(nodes) != 58:
        raise ValueError("Expected exactly 58 original BatchNorm outputs")
    _, aligned, _ = instrument_pir(json.loads(path.read_text()), set(nodes))
    if len(aligned) != 58 or {item["onnx_name"] for item in aligned} != set(nodes):
        raise ValueError("Every requested native BatchNorm must map uniquely")
    for item in aligned:
        node = nodes[item["onnx_name"]]
        validate_attributes(
            attributes(item["attributes"]),
            {value.name: onnx.helper.get_attribute_value(value) for value in node.attribute},
        )


def prepare(output):
    previous = json.loads((PREVIOUS / "protocol.json").read_text())
    report = json.loads((PREVIOUS / "report.json").read_text())
    if not (
        digest(PREVIOUS / "report.json") == REPORT
        and report["controls_valid"]
        and report["sources_unchanged"]
        and report["correction_demonstrated_for_fixture"]
        and report["protocol_sha256"] == digest(PREVIOUS / "protocol.json")
        and report["outputs_sha256"] == digest(PREVIOUS / "outputs.npz")
        and digest(SELECTION) == SELECTION_SHA
    ):
        raise ValueError("Expected unchanged isolated correction and original case selection")
    selected = json.loads(SELECTION.read_text())
    unchanged(selected["sources"])
    unchanged(previous["sources"])
    sources = {**selected["sources"], **previous["sources"]}
    paths = [
        PREVIOUS / "protocol.json",
        PREVIOUS / "report.json",
        PREVIOUS / "outputs.npz",
        SELECTION,
        Path(__file__).resolve(),
        Path(__file__).with_name("batchnorm_graph.py"),
        Path(__file__).parent / "tests/test-batchnorm-graph.py",
        Path(__file__).parent / "tests/test-batchnorm-stage.py",
    ]
    for entry in selected["runs"]:
        paths.append(Path(entry["unfused"]) / "inference.json")
    sources.update({str(path): digest(path) for path in paths})
    unchanged(sources)
    description = (ROOT / "ml/experiments/2026-09-26-s19-ocr-batchnorm-stage.md").read_text()
    output.mkdir(parents=True, mode=0o700, exist_ok=False)
    write(
        output / "protocol.json",
        {
            "rule": RULE,
            "sources": sources,
            "runs": selected["runs"],
            "packages": previous["packages"],
            "machine": machine(),
            "description": description,
        },
    )
    print(
        "Prepared exactly twelve existing cases, two variants, two optimizer levels; no inference."
    )


def run_entry(entry, output, report):
    import numpy as np
    import onnx
    import paddle
    import yaml
    from export_parity import normalized_image
    from model_card import describe
    from ppocr.modeling.architectures import build_model
    from run_identity import validate_inputs
    from stage_parity import compare

    run, unfused = Path(entry["run"]), Path(entry["unfused"])
    dataset, identity = validate_inputs(run)
    describe(run, dataset)
    directory = output / entry["role"]
    directory.mkdir(mode=0o700)
    config = yaml.safe_load((run / "export.yml").read_text())
    dynamic = build_model(config["Architecture"])
    dynamic.set_state_dict(paddle.load(str(run / "selected.pdparams")))
    dynamic.eval()
    control = session(onnx.load(run / "deployment/recognizer.onnx"), "ORT_ENABLE_ALL")
    inputs, expected, control_outputs = [], [], []
    # All original controls precede saved-model candidate evaluation for this run.
    for index, case in enumerate(entry["cases"]):
        pixels = normalized_image(case["image"], case["width"])
        with paddle.no_grad():
            native = dynamic(paddle.to_tensor(pixels)).numpy()
        actual = control.run(None, {control.get_inputs()[0].name: pixels})[0]
        measurement = compare(native, actual)
        valid = all(
            measurement.get(key) == case["prior"][key]
            for key in ["allclose", "same_tokens", "max_absolute_error"]
        )
        row = {
            "role": entry["role"],
            "id": case["id"],
            "width": case["width"],
            "image_sha256": case["image_sha256"],
            "source_group": case["source_group"],
            "original_control_reproduced": valid,
            "original": measurement,
            "variants": {},
        }
        report["cases"].append(row)
        path = directory / f"control-{index}.npz"
        np.savez_compressed(path, input=pixels, paddle=native, original=actual)
        report["artifacts"][str(path.relative_to(output))] = digest(path)
        if not valid:
            raise ValueError("Original control failed; no candidate inference for this run")
        inputs.append(pixels)
        expected.append(native)
        control_outputs.append(row)
    del control, dynamic
    gc.collect()

    original = onnx.load(unfused / "recognizer.onnx")
    native_attributes(original, unfused / "inference.json")
    division, replacements = lower_batchnorm(original)
    if len(replacements) != 58:
        raise ValueError("Incomplete BatchNorm transformation")
    combined, convolution = lower_model(division)
    receipt = {
        "role": entry["role"],
        "identity": identity,
        "batchnorm": replacements,
        "convolution": convolution,
    }
    write(directory / "transformation.json", receipt)
    report["artifacts"][str((directory / "transformation.json").relative_to(output))] = digest(
        directory / "transformation.json"
    )
    report["runs"].append(receipt)
    for name, graph in [("division", division), ("division-convolution", combined)]:
        source = directory / (name + ".onnx")
        onnx.save(graph, source)
        report["artifacts"][str(source.relative_to(output))] = digest(source)
        for level in LEVELS:
            key = name + "-" + level
            path = directory / (key + ".onnx")
            runtime = session(graph, level, path)
            restored = session(onnx.load(path), "ORT_DISABLE_ALL")
            report["artifacts"][str(path.relative_to(output))] = digest(path)
            for index, (pixels, native, row) in enumerate(
                zip(inputs, expected, control_outputs, strict=True)
            ):
                actual = runtime.run(None, {runtime.get_inputs()[0].name: pixels})[0]
                replay = restored.run(None, {restored.get_inputs()[0].name: pixels})[0]
                valid = (
                    actual.shape == replay.shape
                    and actual.dtype == replay.dtype
                    and actual.tobytes() == replay.tobytes()
                )
                row["variants"][key] = {**compare(native, actual), "reload_bitwise_equal": valid}
                arrays = directory / f"{key}-{index}.npz"
                np.savez_compressed(arrays, candidate=actual, reloaded=replay)
                report["artifacts"][str(arrays.relative_to(output))] = digest(arrays)
                if not valid:
                    raise ValueError("Serialized candidate failed exact reload control")
                print(
                    json.dumps(
                        {
                            "role": entry["role"],
                            "case": index,
                            "variant": key,
                            **row["variants"][key],
                        }
                    ),
                    flush=True,
                )
            del runtime, restored
            gc.collect()


def execute(output):
    import paddle

    protocol_path = output / "protocol.json"
    protocol = json.loads(protocol_path.read_text())
    if (
        protocol["rule"] != RULE
        or protocol["machine"] != machine()
        or any(
            importlib.metadata.version(name) != version
            for name, version in protocol["packages"].items()
        )
    ):
        raise ValueError("Frozen rule, host or runtime changed")
    if (
        digest(SELECTION) != SELECTION_SHA
        or protocol["runs"] != json.loads(SELECTION.read_text())["runs"]
    ):
        raise ValueError("Original case selection changed")
    sources = protocol["sources"] | {str(protocol_path): digest(protocol_path)}
    unchanged(sources)
    if {path.name for path in output.iterdir()} != {"protocol.json"}:
        raise ValueError("Execution requires an untouched prepared directory")
    write(output / "execution.json", {"pid": os.getpid(), "protocol_sha256": digest(protocol_path)})
    sys.path.insert(0, str(ROOT / "ml/training/ocr"))
    sys.path.insert(0, str(ROOT / ".local/upstream/PaddleOCR"))
    paddle.set_device("cpu")
    report = {
        "protocol_sha256": digest(protocol_path),
        "qualified": False,
        "full_corpus_started": False,
        "sources_unchanged": False,
        "runs": [],
        "cases": [],
        "artifacts": {},
    }
    try:
        for entry in protocol["runs"]:
            run_entry(entry, output, report)
            gc.collect()
        report.update(decision(report["cases"], protocol["runs"]))
        report["status"] = "bounded-comparison-complete"
        report["next_action"] = (
            "full-corpus-comparison-required"
            if report["selected_for_full_corpus"]
            else "stop-and-diagnose"
        )
    except BaseException as error:
        report.update(
            status="failed-control-or-execution", error_type=type(error).__name__, error=str(error)
        )
        raise
    finally:
        try:
            unchanged(sources)
            unchanged({str(output / path): sha for path, sha in report["artifacts"].items()})
            report["sources_unchanged"] = True
        finally:
            write(output / "report.json", report)
    print(
        json.dumps(
            {
                key: report[key]
                for key in [
                    "variant_passed",
                    "selected_for_full_corpus",
                    "next_action",
                    "qualified",
                ]
            }
        )
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["prepare", "execute"])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / ".local/runs") or output == ROOT / ".local/runs":
        parser.error("Use a new private directory below .local/runs")
    os.umask(0o077)
    (prepare if args.phase == "prepare" else execute)(output)


if __name__ == "__main__":
    main()
