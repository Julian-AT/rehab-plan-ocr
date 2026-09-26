"""Check explicit ONNX division against saved native BatchNorm with/without optimization."""

import argparse
import copy
import importlib.metadata
import json
import os
from pathlib import Path

from batchnorm_fma import REPLAY, measure
from batchnorm_reciprocal import machine
from convolution_lowering import ROOT, digest, unchanged, write

PREVIOUS = ROOT / ".local/runs/ocr-batchnorm-reciprocal-20260926-s19-001"
REPORT = "2c0dee07dcb9fc4f3da274ef867621e2458bc9f636b79110d0111580f88c40e0"
LEVELS = ["ORT_DISABLE_ALL", "ORT_ENABLE_ALL"]
RULE = {
    "scope": "Only the retained first BatchNorm primitive graph and saved synthetic crop.",
    "change": "Replace its sole Reciprocal with Div of unchanged scalar FP32 one by stddev.",
    "controls": "Original graph at both levels must byte-match the saved primitive output first.",
    "reload": "Every retained optimized graph must reproduce its initial result byte-for-byte.",
    "candidate": "At both levels, match saved Paddle and hardware-division output byte-for-byte.",
    "runtime": "CPUExecutionProvider, 2 intra-op / 1 inter-op, same pinned host runtime.",
    "levels": LEVELS,
    "rtol": 1e-3,
    "atol": 1e-5,
    "qualified": False,
    "full_model_started": False,
}


def explicit_division(original):
    """Copy the isolated expression; change one operation without touching its operands."""
    import numpy as np
    import onnx

    if [(item.domain, item.version) for item in original.opset_import] != [("", 17)]:
        raise ValueError("Only the retained opset 17 expression is supported")
    nodes = original.graph.node
    expected = [
        "Add",
        "Sqrt",
        "Reciprocal",
        "Mul",
        "Mul",
        "Mul",
        "Sub",
        "Reshape",
        "Reshape",
        "Mul",
        "Add",
    ]
    if [node.op_type for node in nodes] != expected or any(node.domain for node in nodes):
        raise ValueError("Expected only the isolated Paddle-grouped expression")
    inverse = nodes[2]
    if list(inverse.input) != ["std"] or list(inverse.output) != ["inv"] or inverse.attribute:
        raise ValueError("Unexpected reciprocal signature")
    names = {value.name for value in original.graph.initializer}
    names.update(value for node in nodes for value in [*node.input, *node.output])
    names.update(value.name for value in [*original.graph.input, *original.graph.output])
    if "division_one" in names:
        raise ValueError("New constant would collide with an existing value")
    candidate = copy.deepcopy(original)
    inverse = candidate.graph.node[2]
    inverse.op_type = "Div"
    del inverse.input[:]
    inverse.input.extend(["division_one", "std"])
    candidate.graph.initializer.append(
        onnx.numpy_helper.from_array(np.asarray(1, dtype=np.float32), "division_one")
    )
    onnx.checker.check_model(candidate)
    return candidate


def session(model, level, output=None):
    import onnxruntime as ort

    options = ort.SessionOptions()
    options.graph_optimization_level = getattr(ort.GraphOptimizationLevel, level)
    options.intra_op_num_threads, options.inter_op_num_threads = 2, 1
    if output is not None:
        if output.exists():
            raise ValueError("Retained optimized graph must be new")
        options.optimized_model_filepath = str(output)
    result = ort.InferenceSession(
        model.SerializeToString(), options, providers=["CPUExecutionProvider"]
    )
    result.disable_fallback()
    if result.get_providers() != ["CPUExecutionProvider"]:
        raise ValueError("Unexpected inference provider")
    return result


def prepare(output):
    report = json.loads((PREVIOUS / "report.json").read_text())
    previous = json.loads((PREVIOUS / "protocol.json").read_text())
    if not (
        digest(PREVIOUS / "report.json") == REPORT
        and report["controls_valid"]
        and report["sources_unchanged"]
        and report["expressions"]["hardware-division"]["vs_paddle"]["bitwise_equal"]
        and report["protocol_sha256"] == digest(PREVIOUS / "protocol.json")
        and report["outputs_sha256"] == digest(PREVIOUS / "outputs.npz")
    ):
        raise ValueError("Expected the exact controlled hardware-division result")
    sources = previous["sources"] | {
        str(path): digest(path)
        for path in [
            PREVIOUS / "report.json",
            PREVIOUS / "protocol.json",
            PREVIOUS / "outputs.npz",
            Path(__file__).resolve(),
            Path(__file__).parent / "tests/test-batchnorm-onnx.py",
        ]
    }
    unchanged(sources)
    description = (ROOT / "ml/experiments/2026-09-26-s19-ocr-batchnorm-onnx.md").read_text()
    output.mkdir(parents=True, mode=0o700, exist_ok=False)
    write(
        output / "protocol.json",
        {
            "rule": RULE,
            "sources": sources,
            "packages": previous["packages"],
            "machine": machine(),
            "description": description,
        },
    )
    print("Prepared one ONNX expression change at two fixed optimization levels; no inference.")


def execute(output):
    import numpy as np
    import onnx

    protocol = json.loads((output / "protocol.json").read_text())
    if (
        protocol["rule"] != RULE
        or protocol["machine"] != machine()
        or any(
            importlib.metadata.version(name) != version
            for name, version in protocol["packages"].items()
        )
    ):
        raise ValueError("Prepared rule, host or packages changed")
    sources = protocol["sources"] | {
        str(output / "protocol.json"): digest(output / "protocol.json")
    }
    unchanged(sources)
    if {path.name for path in output.iterdir()} != {"protocol.json"}:
        raise ValueError("Execution requires the untouched prepared directory")
    write(output / "execution.json", {"pid": os.getpid()})
    report = {
        "qualified": False,
        "full_model_started": False,
        "controls_valid": False,
        "protocol_sha256": digest(output / "protocol.json"),
        "runs": {},
    }
    outputs = {}
    try:
        with np.load(REPLAY / "same-input.npz", allow_pickle=False) as saved:
            values = {name: saved[name].copy() for name in saved.files}
        with np.load(PREVIOUS / "outputs.npz", allow_pickle=False) as saved:
            hardware = saved["hardware-division"].copy()
        operand = values["input"]
        if operand.shape != (1, 48, 24, 160) or operand.dtype != np.float32:
            raise ValueError("Fixed operand shape or datatype changed")
        original = onnx.load(REPLAY / "paddle-expression.onnx")
        candidate = explicit_division(original)
        onnx.save(candidate, output / "explicit-division.onnx")
        for name, model in [("control", original), ("division", candidate)]:
            for level in LEVELS:
                identity = name + "-" + level
                path = output / (identity + ".onnx")
                runtime = session(model, level, path)
                actual = runtime.run(None, {"input": operand})[0]
                del runtime
                outputs[identity] = actual
                restored_graph = onnx.load(path)
                restored = session(restored_graph, "ORT_DISABLE_ALL")
                replay = restored.run(None, {"input": operand})[0]
                del restored
                record = {
                    "graph_sha256": digest(path),
                    "optimized_operations": [node.op_type for node in restored_graph.graph.node],
                    "reload_control": measure(actual, replay),
                    "vs_paddle": measure(values["paddle"], actual),
                    "vs_hardware": measure(hardware, actual),
                    "vs_primitive": measure(values["paddle_expression"], actual),
                }
                report["runs"][identity] = record
                if not record["reload_control"]["bitwise_equal"]:
                    raise ValueError("Reloading retained graph changed its result")
                if name == "control" and not record["vs_primitive"]["bitwise_equal"]:
                    raise ValueError("Original expression control differs; no candidate evaluation")
            if name == "control":
                report["controls_valid"] = True
        report["correction_demonstrated_for_fixture"] = all(
            report["runs"]["division-" + level][key]["bitwise_equal"]
            for level in LEVELS
            for key in ["vs_paddle", "vs_hardware"]
        )
        report["status"] = "diagnosed-not-qualified"
    except Exception as error:
        report.update(status="failed-control-or-execution", error=str(error))
        raise
    finally:
        if outputs:
            np.savez_compressed(output / "outputs.npz", **outputs)
            report["outputs_sha256"] = digest(output / "outputs.npz")
        report["sources_unchanged"] = False
        try:
            unchanged(sources)
            report["sources_unchanged"] = True
        finally:
            write(output / "report.json", report)
    print(json.dumps(report, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["prepare", "execute"])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / ".local/runs") or output == ROOT / ".local/runs":
        parser.error("Use a private directory below .local/runs")
    os.umask(0o077)
    (prepare if args.phase == "prepare" else execute)(output)


if __name__ == "__main__":
    main()
