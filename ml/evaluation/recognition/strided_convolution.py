"""Bounded 3x3/stride-two Conv replay and FP32 MatMul lowering; never promote a model."""

import argparse
import copy
import importlib.metadata
import json
import os
from pathlib import Path

from batchnorm_fma import measure
from batchnorm_onnx import LEVELS, session
from batchnorm_reciprocal import machine
from convolution_lowering import ROOT, digest, unchanged, write
from operation_parity import attributes

TRACE = ROOT / ".local/runs/ocr-batchnorm-trace-20260926-s20-001"
REPORT = "197b54e49f2bf92ab848d2d87c34c10ea1bdc1229c3864ea8585dd7c1da06bca"
OUTPUT = "p2o.pd_op.conv2d.3.0"
GEOMETRY = ["zero", "ramp", "top_left", "bottom_right"]
ATTRIBUTES = {
    "dilations": [1, 1],
    "kernel_shape": [3, 3],
    "strides": [2, 2],
    "group": 1,
    "pads": [1, 1, 1, 1],
}
RULE = {
    "scope": "Only the first retained corrected-graph mapped difference, conv2d.3.0.",
    "input": "Use the byte-identical saved concatenation input and unchanged FP32 weights.",
    "controls": "Direct Paddle and original isolated ORT_DISABLE_ALL must match their saved graph outputs byte for byte.",
    "transform": "3x3 kernel, stride two, explicit symmetric padding one: C/KY/KX columns times constant FP32 weights.",
    "geometry": GEOMETRY,
    "levels": LEVELS,
    "reload": "Both saved optimized graphs must reproduce their initial outputs byte for byte.",
    "gate": "All integer geometry cases and the retained Paddle output must match byte for byte at both levels.",
    "rtol": 1e-3,
    "atol": 1e-5,
    "otherwise": "Stop this lowering; do not tune or start a full-graph experiment.",
    "qualified": False,
    "full_graph_automatic": False,
}


def validate(model, operand, weight):
    import numpy as np
    import onnx

    if (
        operand.dtype != np.float32
        or weight.dtype != np.float32
        or operand.ndim != 4
        or operand.shape[0] != 1
        or weight.ndim != 4
        or weight.shape[1] != operand.shape[1]
        or weight.shape[2:] != (3, 3)
        or min(*operand.shape, *weight.shape) <= 0
        or not np.isfinite(operand).all()
        or not np.isfinite(weight).all()
    ):
        raise ValueError("Expected finite FP32 NCHW/OIHW operands, batch one and 3x3 kernel")
    if [(item.domain, item.version) for item in model.opset_import] != [("", 17)]:
        raise ValueError("Expected unchanged opset 17")
    if len(model.graph.input) != 1 or len(model.graph.output) != 1:
        raise ValueError("Expected one input and output")
    nodes = model.graph.node
    if len(nodes) != 2 or [node.op_type for node in nodes] != ["Constant", "Conv"]:
        raise ValueError("Expected an isolated Constant/Conv graph")
    constant, conv = nodes
    if any(node.domain for node in nodes) or model.graph.initializer:
        raise ValueError("Unexpected isolated graph domain or initializers")
    if {a.name: onnx.helper.get_attribute_value(a) for a in conv.attribute} != ATTRIBUTES:
        raise ValueError("Unsupported convolution geometry")
    if (
        len(constant.attribute) != 1
        or constant.attribute[0].name != "value"
        or len(constant.output) != 1
        or constant.input
        or list(conv.input) != [model.graph.input[0].name, constant.output[0]]
        or list(conv.output) != [model.graph.output[0].name]
    ):
        raise ValueError("Unexpected weights or convolution signature")
    encoded = onnx.numpy_helper.to_array(constant.attribute[0].t)
    if not measure(weight, encoded)["bitwise_equal"]:
        raise ValueError("Converted weights changed")
    h, w = operand.shape[2:]
    shape = [1, weight.shape[0], (h + 1) // 2, (w + 1) // 2]
    for value, expected in zip(
        [model.graph.input[0], model.graph.output[0]], [list(operand.shape), shape], strict=True
    ):
        tensor = value.type.tensor_type
        if (
            tensor.elem_type != onnx.TensorProto.FLOAT
            or [dim.dim_value for dim in tensor.shape.dim] != expected
        ):
            raise ValueError("Graph and operand shapes disagree")
    return shape


def lower(model, operand, weight):
    """Keep the retained floating-point operands; only transform patch indexing."""
    import numpy as np
    import onnx

    shape = validate(model, operand, weight)
    h, w = shape[2:]
    nodes, constants = [], []

    def constant(name, value):
        constants.append(onnx.numpy_helper.from_array(np.asarray(value, dtype=np.int64), name))
        return name

    source, target = model.graph.input[0].name, model.graph.output[0].name
    # Isolated intermediates live in a separate namespace; refuse a collision.
    if source.startswith("stride_") or target.startswith("stride_"):
        raise ValueError("Lowering namespace collides with the original graph")
    pads = constant("stride_pads", [0, 0, 1, 1, 0, 0, 1, 1])
    nodes.append(onnx.helper.make_node("Pad", [source, pads], ["stride_padded"], mode="constant"))
    axes = constant("stride_axes", [2, 3])
    steps = constant("stride_steps", [2, 2])
    extra = constant("stride_extra", [2])
    patches = []
    for y in range(3):
        for x in range(3):
            name = f"stride_patch_{y}_{x}"
            start = constant(name + "_start", [y, x])
            end = constant(name + "_end", [y + 2 * h, x + 2 * w])
            nodes.append(
                onnx.helper.make_node("Slice", ["stride_padded", start, end, axes, steps], [name])
            )
            nodes.append(onnx.helper.make_node("Unsqueeze", [name, extra], [name + "_axis"]))
            patches.append(name + "_axis")
    nodes.append(onnx.helper.make_node("Concat", patches, ["stride_patches"], axis=2))
    columns = constant("stride_columns_shape", [1, weight.shape[1] * 9, h * w])
    nodes.append(onnx.helper.make_node("Reshape", ["stride_patches", columns], ["stride_columns"]))
    nodes.append(
        onnx.helper.make_node("Transpose", ["stride_columns"], ["stride_matrix"], perm=[0, 2, 1])
    )
    right = np.ascontiguousarray(weight.reshape(weight.shape[0], -1).T)
    constants.append(onnx.numpy_helper.from_array(right, "stride_weights"))
    nodes.append(
        onnx.helper.make_node("MatMul", ["stride_matrix", "stride_weights"], ["stride_product"])
    )
    nodes.append(
        onnx.helper.make_node("Transpose", ["stride_product"], ["stride_channels"], perm=[0, 2, 1])
    )
    output_shape = constant("stride_output_shape", shape)
    nodes.append(onnx.helper.make_node("Reshape", ["stride_channels", output_shape], [target]))
    graph = onnx.helper.make_graph(
        nodes, "isolated-strided-convolution", model.graph.input, model.graph.output, constants
    )
    result = onnx.helper.make_model(graph, opset_imports=model.opset_import)
    result.ir_version = model.ir_version
    onnx.checker.check_model(result)
    return result


def graph(operand, weight):
    import onnx

    return onnx.helper.make_model(
        onnx.helper.make_graph(
            [
                onnx.helper.make_node(
                    "Constant", [], ["weight"], value=onnx.numpy_helper.from_array(weight)
                ),
                onnx.helper.make_node("Conv", ["input", "weight"], ["output"], **ATTRIBUTES),
            ],
            "strided-geometry",
            [onnx.helper.make_tensor_value_info("input", onnx.TensorProto.FLOAT, operand.shape)],
            [
                onnx.helper.make_tensor_value_info(
                    "output",
                    onnx.TensorProto.FLOAT,
                    [1, weight.shape[0], *((n + 1) // 2 for n in operand.shape[2:])],
                )
            ],
        ),
        opset_imports=[onnx.helper.make_opsetid("", 17)],
        ir_version=8,
    )


def geometry_cases():
    """Independent exact integer sums expose channel order, padding and odd/even sizes."""
    import numpy as np

    weight = (np.arange(54).reshape(2, 3, 3, 3) % 7 - 3).astype(np.float32)
    for name, (h, w) in zip(GEOMETRY, [(4, 6), (5, 7), (5, 6), (4, 7)], strict=True):
        operand = np.zeros((1, 3, h, w), dtype=np.float32)
        if name == "ramp":
            operand[:] = np.arange(3 * h * w).reshape(1, 3, h, w) - 20
        elif name != "zero":
            y, x = (0, 0) if name == "top_left" else (h - 1, w - 1)
            operand[0, :, y, x] = [1, 2, 4]
        expected = np.zeros((1, 2, (h + 1) // 2, (w + 1) // 2), dtype=np.float32)
        for out in range(2):
            for y in range(expected.shape[2]):
                for x in range(expected.shape[3]):
                    total = 0
                    for channel in range(3):
                        for ky in range(3):
                            for kx in range(3):
                                sy, sx = 2 * y + ky - 1, 2 * x + kx - 1
                                if 0 <= sy < h and 0 <= sx < w:
                                    total += int(operand[0, channel, sy, sx]) * int(
                                        weight[out, channel, ky, kx]
                                    )
                    expected[0, out, y, x] = total
        yield name, operand, weight, expected


def decision(rows, controls):
    expected = [(name, level) for name in [*GEOMETRY, "retained"] for level in LEVELS]
    complete = [(row["name"], row["level"]) for row in rows] == expected
    valid = set(controls) == {"input", "weights", "paddle", "onnx"} and all(
        value.get("bitwise_equal") is True for value in controls.values()
    )
    return {
        "controls_valid": valid,
        "lowering_passed": complete
        and valid
        and all(row["bitwise_equal"] and row["reload_bitwise_equal"] for row in rows),
        "qualified": False,
        "full_graph_started": False,
    }


def prepare(output):
    report = json.loads((TRACE / "report.json").read_text())
    prior = json.loads((TRACE / "protocol.json").read_text())
    if not (
        digest(TRACE / "report.json") == REPORT
        and report["protocol_sha256"] == digest(TRACE / "protocol.json")
        and report["controls_valid"]
        and report["sources_unchanged"]
        and report["first_mapped_difference"]["onnx_name"] == OUTPUT
    ):
        raise ValueError("Expected the unchanged controlled trace")
    sources = prior["sources"] | {
        str(path): digest(path)
        for path in [
            TRACE / "report.json",
            TRACE / "protocol.json",
            *[TRACE / name for name in report["artifacts"]],
            Path(__file__).resolve(),
            Path(__file__).parent / "tests/test-strided-convolution.py",
        ]
    }
    unchanged(sources)
    unchanged({str(TRACE / name): value for name, value in report["artifacts"].items()})
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    write(
        output / "protocol.json",
        {
            "rule": RULE,
            "sources": sources,
            "trace": str(TRACE),
            "unfused": prior["unfused"],
            "packages": prior["packages"],
            "machine": machine(),
            "description": (
                ROOT / "ml/experiments/2026-09-26-s20-ocr-strided-convolution.md"
            ).read_text(),
        },
    )
    print("Prepared one isolated strided-convolution experiment; no inference.")


def replay(output, protocol, report):
    import numpy as np
    import onnx
    import paddle

    trace = Path(protocol["trace"])
    previous = json.loads((trace / "report.json").read_text())
    rows = previous["operations"]
    slot = next(i + 1 for i, row in enumerate(rows) if row["onnx_name"] == OUTPUT)
    mapped = rows[slot - 1]
    input_slot = next(
        i + 1 for i, row in enumerate(rows) if row["value_id"] == mapped["input_ids"][0]
    )
    with np.load(trace / "stopping-batch.npz", allow_pickle=False) as saved:
        operand = saved[f"paddle_{input_slot}"].copy()
        other_input = saved[f"onnx_{input_slot}"].copy()
        expected = saved[f"paddle_{slot}"].copy()
        original_output = saved[f"onnx_{slot}"].copy()
    model = onnx.load(trace / "stopping-batch.onnx")
    conv = next(node for node in model.graph.node if OUTPUT in node.output)
    constant = next(node for node in model.graph.node if conv.input[1] in node.output)
    if constant.op_type != "Constant":
        raise ValueError("Expected unchanged constant weights")
    weight = onnx.numpy_helper.to_array(constant.attribute[0].t)
    isolated = onnx.helper.make_model(
        onnx.helper.make_graph(
            [copy.deepcopy(constant), copy.deepcopy(conv)],
            "same-input-strided-convolution",
            [
                onnx.helper.make_tensor_value_info(
                    conv.input[0], onnx.TensorProto.FLOAT, operand.shape
                )
            ],
            [onnx.helper.make_tensor_value_info(OUTPUT, onnx.TensorProto.FLOAT, expected.shape)],
        ),
        opset_imports=model.opset_import,
    )
    isolated.ir_version = model.ir_version
    validate(isolated, operand, weight)
    native = attributes(mapped["attributes"])
    if any(
        native[key] != value
        for key, value in {
            "strides": [2, 2],
            "paddings": [1, 1],
            "padding_algorithm": "EXPLICIT",
            "dilations": [1, 1],
            "groups": 1,
            "data_format": "NCHW",
        }.items()
    ):
        raise ValueError("Native convolution semantics changed")
    paddle.set_device("cpu")
    loaded = paddle.jit.load(str(Path(protocol["unfused"]) / "inference"))
    parameter = loaded._persistable_var_name_dict[conv.input[1]]
    original_weight = loaded.state_dict()[parameter].numpy()
    del loaded
    controls = {"input": measure(operand, other_input), "weights": measure(weight, original_weight)}
    with paddle.no_grad():
        direct = paddle.nn.functional.conv2d(
            paddle.to_tensor(operand), paddle.to_tensor(weight), stride=2, padding=1
        ).numpy()
    controls["paddle"] = measure(expected, direct)
    runtime = session(isolated, "ORT_DISABLE_ALL")
    actual = runtime.run(None, {conv.input[0]: operand})[0]
    controls["onnx"] = measure(original_output, actual)
    del runtime
    report["controls"] = controls
    if not all(value["bitwise_equal"] for value in controls.values()):
        raise ValueError("Same-input original controls did not reproduce")
    onnx.save(isolated, output / "original.onnx")
    np.savez_compressed(
        output / "controls.npz", input=operand, weight=weight, paddle=direct, onnx=actual
    )
    cases = [(name, graph(x, w), x, w, y) for name, x, w, y in geometry_cases()]
    cases.append(("retained", isolated, operand, weight, expected))
    for name, original, x, w, expected in cases:
        candidate = lower(original, x, w)
        onnx.save(candidate, output / f"{name}.onnx")
        for level in LEVELS:
            retained = output / f"{name}-{level}.onnx"
            runtime = session(candidate, level, retained)
            actual = runtime.run(None, {candidate.graph.input[0].name: x})[0]
            del runtime
            restored = session(onnx.load(retained), "ORT_DISABLE_ALL")
            reloaded = restored.run(None, {restored.get_inputs()[0].name: x})[0]
            del restored
            comparison = measure(expected, actual)
            report["cases"].append(
                {
                    "name": name,
                    "level": level,
                    **comparison,
                    "reload_bitwise_equal": measure(actual, reloaded)["bitwise_equal"],
                }
            )
            np.savez_compressed(
                output / f"{name}-{level}.npz", expected=expected, actual=actual, reload=reloaded
            )
    report.update(decision(report["cases"], controls))
    report["status"] = (
        "isolated-correction-demonstrated" if report["lowering_passed"] else "stop-this-lowering"
    )


def execute(output):
    protocol = json.loads((output / "protocol.json").read_text())
    if (
        protocol["rule"] != RULE
        or protocol["machine"] != machine()
        or any(importlib.metadata.version(k) != v for k, v in protocol["packages"].items())
    ):
        raise ValueError("Prepared protocol, machine or packages changed")
    sources = protocol["sources"] | {
        str(output / "protocol.json"): digest(output / "protocol.json")
    }
    unchanged(sources)
    if {path.name for path in output.iterdir()} != {"protocol.json"}:
        raise ValueError("Execution needs the untouched prepared directory")
    write(output / "execution.json", {"pid": os.getpid()})
    report = {
        "protocol_sha256": digest(output / "protocol.json"),
        "cases": [],
        "qualified": False,
        "full_graph_started": False,
    }
    try:
        replay(output, protocol, report)
    except BaseException as error:
        report.update(
            status="failed-control-or-execution", error_type=type(error).__name__, error=str(error)
        )
        raise
    finally:
        report["artifacts"] = {
            path.name: digest(path)
            for path in sorted(output.iterdir())
            if path.suffix in {".npz", ".onnx"}
        }
        report["sources_unchanged"] = False
        try:
            unchanged(sources)
            report["sources_unchanged"] = True
        finally:
            write(output / "report.json", report)
    print(json.dumps({key: report[key] for key in ["status", "lowering_passed", "qualified"]}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["prepare", "execute"])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / ".local/runs"):
        parser.error("Use a private run directory")
    (prepare if args.action == "prepare" else execute)(output)


if __name__ == "__main__":
    main()
