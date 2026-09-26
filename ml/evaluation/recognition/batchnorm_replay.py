"""Replay the retained first BatchNorm difference with identical FP32 operands."""

import argparse
import copy
import importlib.metadata
import json
import os
import shutil
import tempfile
from pathlib import Path

from convolution_lowering import ROOT, digest, unchanged, write
from operation_parity import attributes, compare, instrument_pir

TRACE = ROOT / ".local/runs/ocr-convolution-trace-20260926-s19-001"
TRACE_REPORT = "3445922ce35f5f1961df9e1db39a570acbd47b5c57c558f65391dd7cd44595ac"
OPERATION = "p2o.pd_op.batch_norm_.0.0"
RULE = {
    "scope": "Only the first retained BatchNorm, frozen plan-020 date, width 320.",
    "control": "Copied graph outputs equal uninstrumented controls and retained BN tensors.",
    "operands": "The preceding convolution and all four saved parameters must be bitwise equal.",
    "replay": "Original isolated BatchNorm and exactly two source-derived FP32 expressions.",
    "paddle_bias": "bias - ((mean * inverse_std) * scale)",
    "ort_bias": "bias - (mean * (inverse_std * scale))",
    "runtime": "ORT_DISABLE_ALL, CPUExecutionProvider, 2 intra-op / 1 inter-op threads.",
    "rtol": 1e-3,
    "atol": 1e-5,
    "stop": "Any failed control; no coefficient search, model rewrite or full-corpus run.",
    "qualified": False,
}


def validate_attributes(pir, node):
    """Refuse training or layout conversions instead of guessing equivalent semantics."""
    if (
        pir["is_test"] is not True
        or pir["use_global_stats"] is not True
        or pir["trainable_statistics"] is not False
        or pir["data_format"] != "NCHW"
        or node.get("training_mode", 0) != 0
        or node.get("epsilon", 1e-5) != pir["epsilon"]
        or node.get("momentum", 0.9) != pir["momentum"]
    ):
        raise ValueError("Only identical saved NCHW inference BatchNorm attributes are supported")


def expression_graph(operand, parameters, epsilon, grouping, opset, ir_version):
    import numpy as np
    import onnx

    if grouping not in {"paddle", "ort"}:
        raise ValueError("Only the two predeclared source expressions are allowed")
    if operand.ndim != 4 or operand.dtype != np.float32 or len(parameters) != 4:
        raise ValueError("Expected unchanged FP32 NCHW operand and four parameters")
    if any(p.dtype != np.float32 or p.shape != (operand.shape[1],) for p in parameters):
        raise ValueError("BatchNorm channel parameters disagree")
    constants = [
        onnx.numpy_helper.from_array(value, name)
        for name, value in zip(["scale", "bias", "mean", "variance"], parameters, strict=True)
    ]
    constants += [
        onnx.numpy_helper.from_array(np.asarray(epsilon, dtype=np.float32), "epsilon"),
        onnx.numpy_helper.from_array(np.asarray([1, -1, 1, 1], dtype=np.int64), "shape"),
    ]
    nodes = []

    def op(kind, args, name):
        nodes.append(onnx.helper.make_node(kind, args, [name]))
        return name

    inverse = op(
        "Reciprocal", [op("Sqrt", [op("Add", ["variance", "epsilon"], "v")], "std")], "inv"
    )
    scale = op("Mul", [inverse, "scale"], "new_scale")
    offset = (
        op("Mul", [op("Mul", ["mean", inverse], "mean_inv"), "scale"], "offset")
        if grouping == "paddle"
        else op("Mul", ["mean", scale], "offset")
    )
    bias = op("Sub", ["bias", offset], "new_bias")
    scale4 = op("Reshape", [scale, "shape"], "scale4")
    bias4 = op("Reshape", [bias, "shape"], "bias4")
    op("Add", [op("Mul", ["input", scale4], "scaled"), bias4], "output")
    graph = onnx.helper.make_graph(
        nodes,
        "source-derived-" + grouping,
        [onnx.helper.make_tensor_value_info("input", onnx.TensorProto.FLOAT, operand.shape)],
        [onnx.helper.make_tensor_value_info("output", onnx.TensorProto.FLOAT, operand.shape)],
        constants,
    )
    model = onnx.helper.make_model(graph, opset_imports=opset)
    model.ir_version = ir_version
    onnx.checker.check_model(model)
    return model


def prepare(output):
    if digest(TRACE / "report.json") != TRACE_REPORT:
        raise ValueError("Retained trace identity changed")
    report = json.loads((TRACE / "report.json").read_text())
    previous = json.loads((TRACE / "protocol.json").read_text())
    if (
        not report["controls_valid"]
        or not report["earliest_operation_established"]
        or not report["sources_unchanged"]
        or report["first_mapped_difference"]["onnx_name"] != OPERATION
        or report["protocol_sha256"] != digest(TRACE / "protocol.json")
        or report["first_difference_tensors_sha256"] != digest(TRACE / "first-difference.npz")
    ):
        raise ValueError("Expected controlled first BatchNorm difference")
    sources = dict(previous["sources"])
    for path in [
        TRACE / "report.json",
        TRACE / "protocol.json",
        TRACE / "first-difference.npz",
        Path(__file__).resolve(),
    ]:
        sources[str(path)] = digest(path)
    unchanged(sources)
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    write(output / "protocol.json", {"rule": RULE, "sources": sources, "trace": previous})
    print("Prepared fixed same-input BatchNorm replay; no inference or model change.")


def execute(output):
    import numpy as np
    import onnx
    import onnxruntime as ort
    import paddle

    protocol = json.loads((output / "protocol.json").read_text())
    trace = protocol["trace"]
    if protocol["rule"] != RULE or any(
        importlib.metadata.version(name) != version for name, version in trace["packages"].items()
    ):
        raise ValueError("Prepared rule or runtime changed")
    sources = protocol["sources"] | {
        str(output / "protocol.json"): digest(output / "protocol.json")
    }
    unchanged(sources)
    with (output / "execution.json").open("x") as stream:
        json.dump({"pid": os.getpid(), "protocol_sha256": digest(output / "protocol.json")}, stream)
    report = {"qualified": False, "full_corpus_started": False, "controls_valid": False}
    report["protocol_sha256"] = digest(output / "protocol.json")

    def session(model):
        options = ort.SessionOptions()
        options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_DISABLE_ALL
        options.intra_op_num_threads, options.inter_op_num_threads = 2, 1
        options.log_severity_level = 3
        return ort.InferenceSession(
            model.SerializeToString(), sess_options=options, providers=["CPUExecutionProvider"]
        )

    try:
        paddle.set_device("cpu")
        with np.load(TRACE / "first-difference.npz", allow_pickle=False) as stored:
            pixels, expected_bn, actual_bn = (stored[n] for n in ["pixels", "paddle", "onnx"])
        unfused = Path(trace["unfused"])
        source = json.loads((unfused / "inference.json").read_text())
        graph = onnx.load(trace["candidate"])
        node = next(n for n in graph.graph.node if OPERATION in n.output)
        if node.op_type != "BatchNormalization" or len(node.input) != 5 or len(node.output) != 1:
            raise ValueError("Unexpected first BatchNorm signature")
        copied, aligned, _ = instrument_pir(source, {node.input[0], OPERATION})
        if [row["onnx_name"] for row in aligned] != [node.input[0], OPERATION]:
            raise ValueError("Preceding convolution and BatchNorm alignment changed")
        attr = attributes(aligned[1]["attributes"])
        native_attr = {a.name: onnx.helper.get_attribute_value(a) for a in node.attribute}
        validate_attributes(attr, native_attr)
        control = paddle.jit.load(str(unfused / "inference"))
        control.eval()
        with paddle.no_grad():
            paddle_control = control(paddle.to_tensor(pixels)).numpy()
        native = session(graph)
        onnx_control = native.run(None, {native.get_inputs()[0].name: pixels})[0]
        del native, control
        with tempfile.TemporaryDirectory(prefix=".replay-", dir=output) as temporary:
            folder = Path(temporary)
            (folder / "inference.json").write_text(json.dumps(copied))
            shutil.copyfile(unfused / "inference.pdiparams", folder / "inference.pdiparams")
            model = paddle.jit.load(str(folder / "inference"))
            model.eval()
            with paddle.no_grad():
                expected = [x.numpy() for x in model(paddle.to_tensor(pixels))]
            observed = copy.deepcopy(graph)
            for row in aligned:
                observed.graph.output.append(
                    onnx.helper.make_tensor_value_info(
                        row["onnx_name"], onnx.TensorProto.FLOAT, None
                    )
                )
            native = session(observed)
            actual = native.run(None, {native.get_inputs()[0].name: pixels})
            controls = [
                compare(paddle_control, expected[0]),
                compare(onnx_control, actual[0]),
                compare(expected_bn, expected[2]),
                compare(actual_bn, actual[2]),
                compare(expected[1], actual[1]),
            ]
            report["graph_controls"] = controls
            if not all(c["bitwise_equal"] for c in controls):
                raise ValueError("Instrumentation, saved BatchNorm or preceding operand changed")
            constants = {n.output[0]: n for n in graph.graph.node if n.op_type == "Constant"}
            parameter_nodes = [constants[name] for name in node.input[1:]]
            parameters = [
                onnx.numpy_helper.to_array(n.attribute[0].t).copy() for n in parameter_nodes
            ]
            for name, value in zip(node.input[1:], parameters, strict=True):
                saved = model.state_dict()[model._persistable_var_name_dict[name]].numpy()
                if not np.array_equal(saved, value):
                    raise ValueError("Converted BatchNorm parameter changed")
            operand = expected[1]
            isolated = onnx.helper.make_model(
                onnx.helper.make_graph(
                    [*parameter_nodes, node],
                    "same-input-batchnorm",
                    [
                        onnx.helper.make_tensor_value_info(
                            node.input[0], onnx.TensorProto.FLOAT, operand.shape
                        )
                    ],
                    [
                        onnx.helper.make_tensor_value_info(
                            OPERATION, onnx.TensorProto.FLOAT, operand.shape
                        )
                    ],
                ),
                opset_imports=graph.opset_import,
            )
            isolated.ir_version = graph.ir_version
            onnx.checker.check_model(isolated)
            replay = session(isolated).run(None, {node.input[0]: operand})[0]
            with paddle.no_grad():
                direct = paddle.nn.functional.batch_norm(
                    paddle.to_tensor(operand),
                    paddle.to_tensor(parameters[2]),
                    paddle.to_tensor(parameters[3]),
                    paddle.to_tensor(parameters[0]),
                    paddle.to_tensor(parameters[1]),
                    training=False,
                    momentum=attr["momentum"],
                    epsilon=attr["epsilon"],
                    data_format="NCHW",
                    use_global_stats=True,
                ).numpy()
            report["isolated_controls"] = [compare(expected_bn, direct), compare(actual_bn, replay)]
            if not all(c["bitwise_equal"] for c in report["isolated_controls"]):
                raise ValueError("Isolated operation does not reproduce the retained outputs")
            report["controls_valid"] = True
            report["parameters_bitwise_equal"] = True
            report["expressions"] = {}
            arrays = {"input": operand, "paddle": direct, "onnx": replay}
            for grouping in ["paddle", "ort"]:
                expression = expression_graph(
                    operand,
                    parameters,
                    attr["epsilon"],
                    grouping,
                    graph.opset_import,
                    graph.ir_version,
                )
                value = session(expression).run(None, {"input": operand})[0]
                report["expressions"][grouping] = {
                    "vs_paddle": compare(direct, value),
                    "vs_onnx": compare(replay, value),
                }
                onnx.save(expression, output / (grouping + "-expression.onnx"))
                arrays[grouping + "_expression"] = value
            arrays.update(dict(zip(["scale", "bias", "mean", "variance"], parameters, strict=True)))
            np.savez_compressed(output / "same-input.npz", **arrays)
            onnx.save(isolated, output / "original-batchnorm.onnx")
            report["artifacts"] = {
                p.name: digest(p) for p in output.iterdir() if p.suffix in {".onnx", ".npz"}
            }
        report["status"] = "diagnosed-not-qualified"
    except Exception as error:
        report.update(status="failed-control-or-execution", error=str(error))
        raise
    finally:
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
    for variable in ["OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"]:
        os.environ.setdefault(variable, "2")
    main()
