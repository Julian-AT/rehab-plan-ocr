"""Predeclare at most twelve full-model checks after the isolated convolution gate."""

import argparse
import copy
import gc
import hashlib
import importlib.metadata
import json
import os
import sys
from pathlib import Path

from convolution_lowering import ROOT, digest, lower, unchanged, write

ISOLATED_REPORT = (
    "ocr-convolution-lowering-20260926-s18-001/report.json",
    "461952c1d6f4c01d0c075b82565ae24c93867732a22e38cd13423a2a46b8205b",
)
UNFUSED = {
    "frozen": "fa5c0939559c8e561b9a4843490b3a5be4ec860bd59e053bd152022dde9149fd",
    "full": "26e5df1318b813cf905020f195e6172c63f714738f80b2a6cf29fe4acc751b9e",
}
RULE = {
    "rtol": 1e-3,
    "atol": 1e-5,
    "same_ctc_tokens": True,
    "reference": "Original selected dynamic Paddle model, unchanged float32 preprocessing.",
    "selection": "For each run and width: first failure, worst other failure, first prior pass.",
    "order": "Frozen then full; width 320 then 640; first failure, worst other failure, prior pass.",
    "transform": "Only both group-1 2x2 SAME_UPPER stride/dilation-1 Conv nodes; preserve dynamic shapes.",
    "fail_fast": True,
    "gate": "All 12 cases pass numeric and token checks, with reproduced original controls.",
    "otherwise": "Stop; no full-corpus run or further candidate tuning in this experiment.",
    "qualified": False,
    "full_corpus_automatic": False,
}
RUNTIME = {
    "paddle": "3.3.1",
    "onnxruntime": "1.22.0",
    "provider": "CPUExecutionProvider",
    "intra_op_threads": 2,
    "inter_op_threads": 1,
    "optimization": "ORT_ENABLE_ALL",
}


def select_cases(rows):
    """Selection depends only on immutable prior evidence, never candidate outputs."""
    selected = []
    if len({(r["id"], r["width"]) for r in rows}) != len(rows):
        raise ValueError("Prior evidence contains duplicate cases")
    for width in [320, 640]:
        failures = [
            r for r in rows if r["width"] == width and not (r["allclose"] and r["same_tokens"])
        ]
        passing = [r for r in rows if r["width"] == width and r["allclose"] and r["same_tokens"]]
        if len(failures) < 2 or not passing:
            raise ValueError("Prior evidence cannot supply the predeclared six-case selection")
        first = failures[0]
        worst = max(failures[1:], key=lambda row: row["max_absolute_error"])
        for reason, row in [
            ("first-failure", first),
            ("worst-other-failure", worst),
            ("first-prior-pass", passing[0]),
        ]:
            selected.append({"selection_reason": reason, "prior": row})
    return selected


def dynamic_nodes(conv, weight_node, weight, prefix):
    """Reuse experiment 1's patch order, replacing only its fixed shape constants."""
    import numpy as np
    import onnx

    channels, outputs = weight.shape[1], weight.shape[0]
    operand = np.zeros((1, channels, 1, 1), dtype=np.float32)
    mini = onnx.helper.make_model(
        onnx.helper.make_graph(
            [weight_node, conv],
            "validated-conv-template",
            [
                onnx.helper.make_tensor_value_info(
                    conv.input[0], onnx.TensorProto.FLOAT, operand.shape
                )
            ],
            [
                onnx.helper.make_tensor_value_info(
                    conv.output[0], onnx.TensorProto.FLOAT, [1, outputs, 1, 1]
                )
            ],
        ),
        opset_imports=[onnx.helper.make_opsetid("", 17)],
        ir_version=8,
    )
    template = lower(mini, operand, weight)
    replaced_constants = {
        "column_shape",
        "output_shape",
        *(f"patch_{y}_{x}_end" for y in range(2) for x in range(2)),
    }
    initializers = [
        copy.deepcopy(i) for i in template.graph.initializer if i.name not in replaced_constants
    ]
    for name, values in [
        ("batch_index", [0]),
        ("height_index", [2]),
        ("width_index", [3]),
        ("spatial_indices", [2, 3]),
        ("reduction_size", [channels * 4]),
        ("output_channels", [outputs]),
    ]:
        initializers.append(onnx.numpy_helper.from_array(np.asarray(values, dtype=np.int64), name))
    nodes = [onnx.helper.make_node("Shape", [conv.input[0]], ["input_shape"])]
    for target, index in [
        ("batch", "batch_index"),
        ("height", "height_index"),
        ("width", "width_index"),
        ("spatial", "spatial_indices"),
    ]:
        nodes.append(onnx.helper.make_node("Gather", ["input_shape", index], [target], axis=0))
    nodes.extend(
        [
            onnx.helper.make_node("Mul", ["height", "width"], ["area"]),
            onnx.helper.make_node(
                "Concat", ["batch", "reduction_size", "area"], ["column_shape"], axis=0
            ),
            onnx.helper.make_node(
                "Concat", ["batch", "output_channels", "spatial"], ["output_shape"], axis=0
            ),
        ]
    )
    for y in range(2):
        for x in range(2):
            name = f"patch_{y}_{x}"
            nodes.append(
                onnx.helper.make_node("Add", ["spatial", name + "_start"], [name + "_end"])
            )
    nodes.extend(copy.deepcopy(list(template.graph.node)))
    external = {conv.input[0], conv.output[0]}
    for initializer in initializers:
        initializer.name = prefix + initializer.name
    for node in nodes:
        for names in [node.input, node.output]:
            for i, name in enumerate(names):
                if name not in external:
                    names[i] = prefix + name
        node.name = prefix + node.op_type + "/" + node.output[0]
    return nodes, initializers


def lower_model(model):
    """Copy an unfused graph; leave every other node and original constant byte-identical."""
    import onnx

    if [(o.domain, o.version) for o in model.opset_import] != [("", 17)]:
        raise ValueError("Expected original opset 17")
    constants = {n.output[0]: n for n in model.graph.node if n.op_type == "Constant"}
    original_names = {v for n in model.graph.node for v in [*n.input, *n.output]}
    if any(name.startswith("conv_lowering/") for name in original_names):
        raise ValueError("Candidate namespace already exists")
    result = copy.deepcopy(model)
    del result.graph.node[:]
    replacements = []
    for node in model.graph.node:
        attrs = {a.name: onnx.helper.get_attribute_value(a) for a in node.attribute}
        if node.op_type != "Conv" or attrs.get("kernel_shape") != [2, 2]:
            result.graph.node.append(node)
            continue
        weight_node = constants.get(node.input[1])
        if weight_node is None:
            raise ValueError("Expected original constant convolution weights")
        weight = onnx.numpy_helper.to_array(weight_node.attribute[0].t)
        prefix = f"conv_lowering/{len(replacements)}/"
        nodes, initializers = dynamic_nodes(node, weight_node, weight, prefix)
        result.graph.node.extend(nodes)
        result.graph.initializer.extend(initializers)
        replacements.append(
            {
                "output": node.output[0],
                "weight_shape": list(weight.shape),
                "weight_sha256": hashlib.sha256(weight.tobytes()).hexdigest(),
            }
        )
    if [row["weight_shape"] for row in replacements] != [[24, 48, 2, 2], [48, 24, 2, 2]]:
        raise ValueError("Expected exactly the two original stem convolutions")
    retained = [
        n.SerializeToString() for n in result.graph.node if not n.name.startswith("conv_lowering/")
    ]
    expected = [
        n.SerializeToString()
        for n in model.graph.node
        if not (n.op_type == "Conv" and any(n.output[0] == r["output"] for r in replacements))
    ]
    if retained != expected:
        raise ValueError("An unrelated source operation changed")
    onnx.checker.check_model(result)
    return result, replacements


def prepare(output):
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    sources = {}

    def retain(path, expected=None):
        actual = digest(path)
        if expected is not None and actual != expected:
            raise ValueError("Selected source identity changed")
        sources[str(path)] = actual
        return json.loads(path.read_text()) if path.suffix == ".json" else None

    isolated = retain(ROOT / ".local/runs" / ISOLATED_REPORT[0], ISOLATED_REPORT[1])
    if not isolated["experiment_1_passed"] or not isolated["controls_valid"]:
        raise ValueError("Experiment 1 gate is closed")
    for name in [
        "convolution_stage.py",
        "convolution_lowering.py",
        "operation_parity.py",
        "export_parity.py",
        "stage_parity.py",
    ]:
        retain(Path(__file__).with_name(name).resolve())
    runs = []
    for role, report_hash in UNFUSED.items():
        run = ROOT / ".local/runs" / f"ocr-synthetic-{role}-001"
        unfused = ROOT / ".local/runs" / f"ocr-unfused-{role}-diagnostic-20260926-s18-001"
        evidence = retain(unfused / "report.json", report_hash)
        for name, expected in evidence["sources"].items():
            retain(run / name, expected)
        for name, expected in evidence["unfused_export"]["artifacts"].items():
            retain(unfused / name, expected)
        for name in ["settings.json", "selection.json", "identity.json"]:
            retain(run / name)
        settings = json.loads((run / "settings.json").read_text())
        dataset_path = Path(settings["dataset"])
        dataset = retain(dataset_path)
        records = {r["id"]: r for r in dataset["samples"]}
        prior = json.loads((run / "deployment/parity.json").read_text())
        cases = select_cases(prior["cases"])
        for case in cases:
            row = records[case["prior"]["id"]]
            image = dataset_path.parent / row["image"]
            retain(image, row["image_sha256"])
            case.update(
                id=row["id"],
                width=case["prior"]["width"],
                image=str(image),
                image_sha256=row["image_sha256"],
                source_group=row["group"],
            )
        runs.append({"role": role, "run": str(run), "unfused": str(unfused), "cases": cases})
    unchanged(sources)
    write(
        output / "protocol.json",
        {
            "schema_version": 1,
            "rule": RULE,
            "runtime": RUNTIME,
            "sources": sources,
            "runs": runs,
            "packages": {
                name: importlib.metadata.version(name)
                for name in [
                    "numpy",
                    "onnx",
                    "onnxruntime",
                    "paddlepaddle",
                    "opencv-contrib-python",
                ]
            },
        },
    )
    print(
        "Prepared exact IDs and pixel hashes for 12 cases; no models loaded or inference performed."
    )


def execute(output):
    import onnx
    import onnxruntime as ort
    import paddle
    import yaml
    from export_parity import normalized_image

    protocol_path = output / "protocol.json"
    protocol = json.loads(protocol_path.read_text())
    if protocol["rule"] != RULE or protocol["runtime"] != RUNTIME:
        raise ValueError("Predeclared protocol changed")
    if ort.__version__ != "1.22.0" or paddle.__version__ != "3.3.1":
        raise ValueError("Pinned runtimes changed")
    if any(
        importlib.metadata.version(name) != version
        for name, version in protocol["packages"].items()
    ):
        raise ValueError("Prepared package environment changed")
    sources = {**protocol["sources"], str(protocol_path): digest(protocol_path)}
    unchanged(sources)
    with (output / "execution.json").open("x") as stream:
        json.dump({"pid": os.getpid(), "protocol_sha256": digest(protocol_path)}, stream)
    sys.path.insert(0, str(ROOT / "ml/training/ocr"))
    from model_card import describe
    from run_identity import validate_inputs
    from stage_parity import compare

    sys.path.insert(0, str(ROOT / ".local/upstream/PaddleOCR"))
    from ppocr.modeling.architectures import build_model

    report = {
        "protocol_sha256": digest(protocol_path),
        "qualified": False,
        "runs": [],
        "cases": [],
        "full_corpus_started": False,
        "sources_unchanged": False,
    }
    options = ort.SessionOptions()
    options.intra_op_num_threads, options.inter_op_num_threads = 2, 1
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    paddle.set_device("cpu")
    stopped = False
    for entry in protocol["runs"]:
        run, unfused = Path(entry["run"]), Path(entry["unfused"])
        dataset, identity = validate_inputs(run)
        describe(run, dataset)
        candidate_dir = output / entry["role"]
        candidate_dir.mkdir(mode=0o700)
        original_graph = onnx.load(unfused / "recognizer.onnx")
        candidate, replacements = lower_model(original_graph)
        candidate_path = candidate_dir / "recognizer.onnx"
        onnx.save(candidate, candidate_path)
        del candidate, original_graph
        gc.collect()
        receipt = {
            "role": entry["role"],
            "identity_verification": identity,
            "replacements": replacements,
            "artifact_sha256": digest(candidate_path),
        }
        write(candidate_dir / "transformation.json", receipt)
        report["runs"].append(receipt)
        config = yaml.safe_load((run / "export.yml").read_text())
        dynamic = build_model(config["Architecture"])
        dynamic.set_state_dict(paddle.load(str(run / "selected.pdparams")))
        dynamic.eval()
        sessions = {
            name: ort.InferenceSession(
                str(path), sess_options=options, providers=["CPUExecutionProvider"]
            )
            for name, path in [
                ("original", run / "deployment/recognizer.onnx"),
                ("unfused", unfused / "recognizer.onnx"),
                ("candidate", candidate_path),
            ]
        }
        with paddle.no_grad():
            for case in entry["cases"]:
                pixels = normalized_image(case["image"], case["width"])
                expected = dynamic(paddle.to_tensor(pixels)).numpy()
                comparisons = {}
                for name, session in sessions.items():
                    actual = session.run(None, {session.get_inputs()[0].name: pixels})[0]
                    comparisons[name] = compare(expected, actual)
                original = comparisons["original"]
                control = all(
                    original[k] == case["prior"][k]
                    for k in ["allclose", "same_tokens", "max_absolute_error"]
                )
                row = {
                    "role": entry["role"],
                    "id": case["id"],
                    "width": case["width"],
                    "image_sha256": case["image_sha256"],
                    "original_control_reproduced": control,
                    **comparisons,
                }
                report["cases"].append(row)
                if not control or not (
                    comparisons["candidate"]["allclose"] and comparisons["candidate"]["same_tokens"]
                ):
                    stopped = True
                    break
        if digest(candidate_path) != receipt["artifact_sha256"]:
            raise ValueError("Candidate graph changed during inference")
        del sessions, dynamic
        gc.collect()
        if stopped:
            break
    unchanged(sources)
    report.update(
        sources_unchanged=True,
        experiment_2_passed=not stopped and len(report["cases"]) == 12,
        next_action="stop-and-diagnose" if stopped else "full-corpus-comparison-required",
    )
    write(output / "report.json", report)
    print(json.dumps({k: report[k] for k in ["experiment_2_passed", "next_action", "qualified"]}))


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
