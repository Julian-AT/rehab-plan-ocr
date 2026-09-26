"""Predeclare and replay a bounded FP32 Conv-to-MatMul experiment, without Paddle."""

import argparse
import importlib.metadata
import json
import os
import platform
import sys
from pathlib import Path

from operation_parity import ROOT, compare, digest

FIXTURES = {
    "frozen": (
        "ocr-operation-frozen-20260926-s18-001",
        "b17c28f4068cb5e02317ab443ad382b1c7d7be5249b028ae729a3b5781bcf67b",
    ),
    "full": (
        "ocr-operation-full-20260926-s18-001",
        "b82f3ce31b38f250b76a8255db2765a5b2e89e39d5629f83ac1fc46842752793",
    ),
}
RULE = {
    "decision": "Both stored Paddle outputs must match byte-for-byte and all geometry cases pass.",
    "otherwise": "Stop this approach; do not start experiment 2.",
    "controls": "Original ONNX replay must match its stored output byte-for-byte.",
    "reference": "Existing float32 Paddle arrays; never float64 or a redefined model.",
    "rtol": 1e-3,
    "atol": 1e-5,
    "qualified": False,
    "experiment_2_automatic": False,
}
RUNTIME = {
    "onnxruntime": "1.22.0",
    "provider": "CPUExecutionProvider",
    "intra_op_threads": 2,
    "inter_op_threads": 1,
    "graph_optimization": "ORT_DISABLE_ALL",
    "prepacking": True,
}


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")
    path.chmod(0o600)


def unchanged(sources):
    for name, expected in sources.items():
        if digest(Path(name)) != expected:
            raise ValueError(f"Changed experiment input: {Path(name).name}")


def validate_conv(model, operand, weight):
    """Accept only the two retained fixtures' explicitly understood operator semantics."""
    import numpy as np
    import onnx

    if operand.dtype != np.float32 or weight.dtype != np.float32:
        raise ValueError("Only unchanged float32 operands are allowed")
    if operand.ndim != 4 or operand.shape[0] != 1 or weight.ndim != 4:
        raise ValueError("Expected one NCHW image and OIHW weights")
    if weight.shape[1] != operand.shape[1] or weight.shape[2:] != (2, 2):
        raise ValueError("Expected matching channels and a 2x2 kernel")
    if list((o.domain, o.version) for o in model.opset_import) != [("", 17)]:
        raise ValueError("Only the original opset 17 is supported")
    if len(model.graph.input) != 1 or len(model.graph.output) != 1:
        raise ValueError("Expected one input and output")
    nodes = model.graph.node
    if len(nodes) != 2 or nodes[0].op_type != "Constant" or nodes[1].op_type != "Conv":
        raise ValueError("Expected the retained Constant/Conv graph")
    conv = nodes[1]
    attrs = {a.name: onnx.helper.get_attribute_value(a) for a in conv.attribute}
    if attrs != {
        "dilations": [1, 1],
        "kernel_shape": [2, 2],
        "strides": [1, 1],
        "group": 1,
        "auto_pad": b"SAME_UPPER",
    }:
        raise ValueError("Unsupported convolution geometry; do not guess padding")
    if list(conv.input) != [model.graph.input[0].name, nodes[0].output[0]]:
        raise ValueError("Unexpected Conv inputs or bias")
    if list(conv.output) != [model.graph.output[0].name]:
        raise ValueError("Unexpected Conv output")
    encoded = onnx.numpy_helper.to_array(nodes[0].attribute[0].t)
    if encoded.dtype != weight.dtype or encoded.shape != weight.shape:
        raise ValueError("Fixture weight shape or dtype changed")
    if encoded.tobytes() != weight.tobytes():
        raise ValueError("Fixture and graph weights must be byte-identical")
    expected_shapes = [list(operand.shape), [1, weight.shape[0], *operand.shape[2:]]]
    for value, shape in zip(
        [*model.graph.input, *model.graph.output], expected_shapes, strict=True
    ):
        tensor = value.type.tensor_type
        if tensor.elem_type != onnx.TensorProto.FLOAT:
            raise ValueError("Graph tensors must be float32")
        if [d.dim_value for d in tensor.shape.dim] != shape:
            raise ValueError("Graph and fixture shapes disagree")


def lower(model, operand, weight):
    """Exact index transformation: patches[N,HW,C*KH*KW] @ constant weights[K,O]."""
    import numpy as np
    import onnx

    validate_conv(model, operand, weight)
    h, w = operand.shape[2:]
    initializers, nodes = [], []

    def constant(name, value):
        initializers.append(onnx.numpy_helper.from_array(np.asarray(value, dtype=np.int64), name))
        return name

    source, target = model.graph.input[0].name, model.graph.output[0].name
    # SAME_UPPER for an even 2x2 kernel and stride one pads only bottom/right.
    pads = constant("pads", [0, 0, 0, 0, 0, 0, 1, 1])
    nodes.append(onnx.helper.make_node("Pad", [source, pads], ["padded"], mode="constant"))
    axes, extra_axis = constant("spatial_axes", [2, 3]), constant("kernel_axis", [2])
    patches = []
    for y in range(2):
        for x in range(2):
            name = f"patch_{y}_{x}"
            start = constant(name + "_start", [y, x])
            end = constant(name + "_end", [h + y, w + x])
            nodes.append(onnx.helper.make_node("Slice", ["padded", start, end, axes], [name]))
            nodes.append(onnx.helper.make_node("Unsqueeze", [name, extra_axis], [name + "_axis"]))
            patches.append(name + "_axis")
    nodes.append(onnx.helper.make_node("Concat", patches, ["patches"], axis=2))
    shape = constant("column_shape", [1, weight.shape[1] * 4, h * w])
    nodes.append(onnx.helper.make_node("Reshape", ["patches", shape], ["columns"]))
    nodes.append(onnx.helper.make_node("Transpose", ["columns"], ["matrix"], perm=[0, 2, 1]))
    right = np.ascontiguousarray(weight.reshape(weight.shape[0], -1).T)
    initializers.append(onnx.numpy_helper.from_array(right, "right_weights"))
    nodes.append(onnx.helper.make_node("MatMul", ["matrix", "right_weights"], ["product"]))
    nodes.append(onnx.helper.make_node("Transpose", ["product"], ["channels"], perm=[0, 2, 1]))
    shape = constant("output_shape", [1, weight.shape[0], h, w])
    nodes.append(onnx.helper.make_node("Reshape", ["channels", shape], [target]))
    graph = onnx.helper.make_graph(
        nodes, "isolated-convolution-lowering", model.graph.input, model.graph.output, initializers
    )
    result = onnx.helper.make_model(graph, opset_imports=model.opset_import)
    result.ir_version = model.ir_version
    onnx.checker.check_model(result)
    return result


def geometry_cases():
    """Small exact integer stencils distinguish channel order and asymmetric padding."""
    import numpy as np

    weight = (np.arange(24, dtype=np.int32).reshape(2, 3, 2, 2) % 5 - 2).astype(np.float32)
    for name in ["zero", "ramp", "top_left", "bottom_right"]:
        operand = np.zeros((1, 3, 3, 5), dtype=np.float32)
        if name == "ramp":
            operand[:] = np.arange(45).reshape(1, 3, 3, 5) - 20
        elif name != "zero":
            y, x = (0, 0) if name == "top_left" else (2, 4)
            operand[0, :, y, x] = [1, 2, 4]
        expected = np.zeros((1, 2, 3, 5), dtype=np.float32)
        for out in range(2):
            for y in range(3):
                for x in range(5):
                    total = 0
                    for channel in range(3):
                        for ky in range(2):
                            for kx in range(2):
                                if y + ky < 3 and x + kx < 5:
                                    total += int(operand[0, channel, y + ky, x + kx]) * int(
                                        weight[out, channel, ky, kx]
                                    )
                    expected[0, out, y, x] = total
        yield name, operand, weight, expected


def conv_graph(operand, weight):
    import onnx

    return onnx.helper.make_model(
        onnx.helper.make_graph(
            [
                onnx.helper.make_node(
                    "Constant", [], ["weight"], value=onnx.numpy_helper.from_array(weight)
                ),
                onnx.helper.make_node(
                    "Conv",
                    ["input", "weight"],
                    ["output"],
                    dilations=[1, 1],
                    kernel_shape=[2, 2],
                    strides=[1, 1],
                    group=1,
                    auto_pad="SAME_UPPER",
                ),
            ],
            "integer-geometry-control",
            [onnx.helper.make_tensor_value_info("input", onnx.TensorProto.FLOAT, operand.shape)],
            [
                onnx.helper.make_tensor_value_info(
                    "output", onnx.TensorProto.FLOAT, [1, weight.shape[0], *operand.shape[2:]]
                )
            ],
        ),
        opset_imports=[onnx.helper.make_opsetid("", 17)],
        ir_version=8,
    )


def prepare(output):
    import numpy as np
    import onnx

    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    sources = {str(Path(__file__).resolve()): digest(Path(__file__))}
    sources[str(Path(__file__).with_name("operation_parity.py"))] = digest(
        Path(__file__).with_name("operation_parity.py")
    )
    cases = []
    for role, (directory, report_hash) in FIXTURES.items():
        folder = ROOT / ".local/runs" / directory
        report = folder / "report.json"
        if digest(report) != report_hash:
            raise ValueError("Retained operation report changed")
        sources[str(report)] = report_hash
        evidence = json.loads(report.read_text())["cases"][0]["isolated_first_difference"]
        for name, expected_hash in evidence["artifacts"].items():
            path = folder / name
            if digest(path) != expected_hash:
                raise ValueError("Retained operation fixture changed")
            sources[str(path)] = expected_hash
        # Deliberately do not load the archive's reference_float64 member.
        fixture = folder / "first-convolution.npz"
        with np.load(fixture, allow_pickle=False) as arrays:
            operand, weight = arrays["input"], arrays["weight"]
        original = folder / "first-convolution.onnx"
        lowered = output / f"{role}.onnx"
        onnx.save(lower(onnx.load(original), operand, weight), lowered)
        cases.append(
            {
                "name": role,
                "fixture": str(fixture),
                "original": str(original),
                "lowered": lowered.name,
                "kind": "retained",
            }
        )
    for name, operand, weight, expected in geometry_cases():
        model = conv_graph(operand, weight)
        lowered = output / f"geometry-{name}.onnx"
        onnx.save(lower(model, operand, weight), lowered)
        fixture = output / f"geometry-{name}.npz"
        np.savez_compressed(fixture, input=operand, expected=expected)
        cases.append(
            {"name": name, "fixture": str(fixture), "lowered": lowered.name, "kind": "geometry"}
        )
    unchanged(sources)
    files = {p.name: digest(p) for p in output.iterdir()}
    for path in output.iterdir():
        path.chmod(0o600)
    protocol = {
        "schema_version": 1,
        "kind": "isolated-convolution-lowering",
        "rule": RULE,
        "sources": sources,
        "prepared_files": files,
        "cases": cases,
        "runtime": RUNTIME,
        "environment": {
            "python": sys.version,
            "platform": platform.platform(),
            "packages": {
                name: importlib.metadata.version(name) for name in ["numpy", "onnx", "onnxruntime"]
            },
        },
    }
    write(output / "protocol.json", protocol)
    print("Prepared two retained fixtures and four geometry cases; no inference performed.")


def decision(rows):
    retained = [r for r in rows if r["kind"] == "retained"]
    geometry = [r for r in rows if r["kind"] == "geometry"]
    controls = (
        len(retained) == 2
        and {r["name"] for r in retained} == {"frozen", "full"}
        and all(r["control_bitwise_equal"] for r in retained)
    )
    complete_geometry = len(geometry) == 4 and {r["name"] for r in geometry} == {
        "zero",
        "ramp",
        "top_left",
        "bottom_right",
    }
    passed = (
        controls and complete_geometry and len(rows) == 6 and all(r["bitwise_equal"] for r in rows)
    )
    return {
        "controls_valid": controls,
        "experiment_1_passed": passed,
        "next_action": "experiment-2-may-be-planned" if passed else "stop-this-approach",
        "qualified": False,
        "experiment_2_started": False,
    }


def execute(output):
    import numpy as np
    import onnxruntime as ort

    protocol_path = output / "protocol.json"
    protocol = json.loads(protocol_path.read_text())
    if (
        protocol["rule"] != RULE
        or protocol["runtime"] != RUNTIME
        or importlib.metadata.version("onnxruntime") != "1.22.0"
    ):
        raise ValueError("Predeclared rule or pinned runtime changed")
    sources = {**protocol["sources"], str(protocol_path): digest(protocol_path)}
    sources.update({str(output / p): h for p, h in protocol["prepared_files"].items()})
    unchanged(sources)
    if (output / "report.json").exists():
        raise ValueError("Completed experiments are immutable; use a new preparation")
    with (output / "execution.json").open("x") as stream:
        json.dump({"pid": os.getpid(), "protocol_sha256": digest(protocol_path)}, stream)
    options = ort.SessionOptions()
    options.intra_op_num_threads, options.inter_op_num_threads = 2, 1
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_DISABLE_ALL
    rows = []

    def infer(path, operand):
        session = ort.InferenceSession(
            str(path), sess_options=options, providers=["CPUExecutionProvider"]
        )
        return session.run(None, {session.get_inputs()[0].name: operand})[0]

    def exact(left, right):
        return (
            left.dtype == right.dtype
            and left.shape == right.shape
            and left.tobytes() == right.tobytes()
        )

    for case in protocol["cases"]:
        with np.load(case["fixture"], allow_pickle=False) as arrays:
            operand = arrays["input"]
            expected = arrays["paddle" if case["kind"] == "retained" else "expected"]
            actual = infer(output / case["lowered"], operand)
            row = {
                "name": case["name"],
                "kind": case["kind"],
                **compare(expected, actual),
                "bitwise_equal": exact(expected, actual),
                "different_float32_bit_patterns": int(
                    np.count_nonzero(expected.view("uint32") != actual.view("uint32"))
                ),
            }
            if case["kind"] == "retained":
                control = infer(case["original"], operand)
                row["control_bitwise_equal"] = exact(arrays["onnx"], control)
                row["original_vs_paddle"] = compare(expected, control)
            rows.append(row)
    unchanged(sources)
    report = {
        "protocol_sha256": digest(protocol_path),
        "sources_unchanged": True,
        "cases": rows,
        **decision(rows),
    }
    write(output / "report.json", report)
    print(json.dumps({k: report[k] for k in ("experiment_1_passed", "next_action", "qualified")}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["prepare", "execute"])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / ".local/runs") or output == ROOT / ".local/runs":
        parser.error("Use a private experiment directory below .local/runs")
    os.umask(0o077)
    (prepare if args.phase == "prepare" else execute)(output)


if __name__ == "__main__":
    main()
