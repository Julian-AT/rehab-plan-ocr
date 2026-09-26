"""Trace saved Paddle/ONNX intermediates without changing deployment evidence."""

import argparse
import collections
import copy
import gc
import hashlib
import json
import os
import resource
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def outputs(operation):
    values = operation.get("O", [])
    return values if isinstance(values, list) else [values]


def instrument_pir(source, available):
    """Add only fetches to a copied, version-checked PIR program; keep all SSA operations."""
    graph = copy.deepcopy(source)
    if graph["base_code"] != {"magic": "pir", "trainable": True, "version": 4}:
        raise ValueError("Unsupported Paddle serialization; do not guess operation identities")
    regions = graph["program"]["regions"]
    if len(regions) != 1 or len(regions[0]["blocks"]) != 1:
        raise ValueError("Only a single inference block is supported")
    operations = regions[0]["blocks"][0]["ops"]
    fetches = [op for op in operations if op["#"] == "1.fetch"]
    if len(fetches) != 1:
        raise ValueError("Expected exactly one original CTC output")
    next_value = max(v["%"] for op in operations for v in outputs(op)) + 1
    counts, aligned, missing = collections.Counter(), [], []
    for index, op in enumerate(operations[:]):
        kind = op["#"]
        ordinal = counts[kind]
        counts[kind] += 1
        if not kind.startswith("1.") or kind in {"1.data", "1.fetch"}:
            continue
        for slot, value in enumerate(outputs(op)):
            if value.get("TT", {}).get("D", [{}])[0].get("#") != "0.t_f32":
                continue
            name = f"p2o.pd_op.{kind[2:]}.{ordinal}.{slot}"
            if name not in available:
                missing.append({"program_index": index, "name": name})
                continue
            aligned.append(
                {
                    "program_index": index,
                    "operation": kind[2:],
                    "onnx_name": name,
                    "value_id": value["%"],
                    "input_ids": [v["%"] for v in op.get("I", [])],
                    "attributes": op.get("A", []),
                }
            )
            fetch = copy.deepcopy(fetches[0])
            fetch["I"] = [{"%": value["%"]}]
            fetch["O"] = [copy.deepcopy(value)]
            fetch["O"][0]["%"] = next_value
            next_value += 1
            for attr in fetch["A"]:
                if attr["N"] == "name":
                    attr["AT"]["D"] = name
                elif attr["N"] == "col":
                    attr["AT"]["D"] = len(aligned)
            operations.append(fetch)
    if not aligned:
        raise ValueError("No matching intermediate outputs")
    return graph, aligned, missing


def compare(expected, actual):
    import numpy as np

    if expected.shape != actual.shape or expected.dtype != actual.dtype:
        raise ValueError("Aligned operation shape or dtype disagrees")
    if not np.isfinite(expected).all() or not np.isfinite(actual).all():
        raise ValueError("Nonfinite intermediate output")
    difference = np.abs(expected - actual)
    return {
        "shape": list(actual.shape),
        "bitwise_equal": bool(np.array_equal(expected, actual)),
        "allclose": bool(np.allclose(expected, actual, rtol=1e-3, atol=1e-5)),
        "max_absolute_error": float(difference.max()),
        "failed_values": int(np.count_nonzero(difference > 1e-5 + 1e-3 * np.abs(actual))),
        "total_values": int(actual.size),
    }


def first_differences(rows):
    return {
        name: next((row for row in rows if not row[field]), None)
        for name, field in [
            ("first_bit_difference", "bitwise_equal"),
            ("first_outside_tolerance", "allclose"),
        ]
    }


def attributes(operation):
    def decode(value):
        data = value["D"]
        return [decode(v) for v in data] if value["#"] == "0.a_array" else data

    return {attr["N"]: decode(attr["AT"]) for attr in operation}


def isolate_convolution(folder, row, aligned, expected, pixels, source, graph, model, options):
    """Same-input kernel replay, preserving converted weights and exported attributes."""
    import numpy as np
    import onnx
    import onnxruntime as ort
    import paddle

    if row is None or row["operation"] not in {"conv2d", "depthwise_conv2d"}:
        return None
    mapped = next(item for item in aligned if item["onnx_name"] == row["onnx_name"])
    source_slot = next(
        (
            index + 1
            for index, item in enumerate(aligned)
            if item["value_id"] == mapped["input_ids"][0]
        ),
        None,
    )
    node = next(n for n in graph.graph.node if row["onnx_name"] in n.output)
    if source_slot is None and node.input[0] not in {v.name for v in graph.graph.input}:
        return {"status": "input-not-an-aligned-intermediate"}
    operand = pixels if source_slot is None else expected[source_slot]
    constants = {n.output[0]: n for n in graph.graph.node if n.op_type == "Constant"}
    weight_node = constants[node.input[1]]
    weight = onnx.numpy_helper.to_array(weight_node.attribute[0].t)
    # This pinned Paddle loader provides the original saved parameter-name map.
    parameter_name = model._persistable_var_name_dict[node.input[1]]
    saved_weight = model.state_dict()[parameter_name].numpy()
    if not np.array_equal(weight, saved_weight):
        raise ValueError("Converted convolution weights changed")
    shape = row["shape"]
    isolated = onnx.helper.make_model(
        onnx.helper.make_graph(
            [weight_node, node],
            "same-input-convolution",
            [
                onnx.helper.make_tensor_value_info(
                    node.input[0], onnx.TensorProto.FLOAT, list(operand.shape)
                )
            ],
            [onnx.helper.make_tensor_value_info(node.output[0], onnx.TensorProto.FLOAT, shape)],
        ),
        opset_imports=graph.opset_import,
    )
    isolated.ir_version = graph.ir_version
    model_path = folder / "first-convolution.onnx"
    onnx.save(isolated, model_path)
    session = ort.InferenceSession(
        str(model_path), sess_options=options, providers=["CPUExecutionProvider"]
    )
    actual = session.run(None, {node.input[0]: operand})[0]
    attr = attributes(mapped["attributes"])
    padding = (
        attr["paddings"] if attr["padding_algorithm"] == "EXPLICIT" else attr["padding_algorithm"]
    )
    kwargs = dict(
        stride=attr["strides"], padding=padding, dilation=attr["dilations"], groups=attr["groups"]
    )
    with paddle.no_grad():
        direct = paddle.nn.functional.conv2d(
            paddle.to_tensor(operand), paddle.to_tensor(weight), **kwargs
        ).numpy()
        reference = paddle.nn.functional.conv2d(
            paddle.to_tensor(operand.astype("float64")),
            paddle.to_tensor(weight.astype("float64")),
            **kwargs,
        ).numpy()
    slot = next(i + 1 for i, item in enumerate(aligned) if item["onnx_name"] == row["onnx_name"])
    tensors = folder / "first-convolution.npz"
    np.savez_compressed(
        tensors,
        input=operand,
        weight=weight,
        paddle=direct,
        onnx=actual,
        reference_float64=reference,
    )
    return {
        "status": "same-input-replayed",
        "operation": row["onnx_name"],
        "weights_bitwise_equal": True,
        "paddle_direct_vs_saved_graph": compare(expected[slot], direct),
        "same_input_runtime_comparison": compare(direct, actual),
        "float64_reference_max_error": {
            "paddle": float(np.abs(reference - direct).max()),
            "onnx": float(np.abs(reference - actual).max()),
        },
        "artifacts": {p.name: digest(p) for p in [model_path, tensors]},
        "source_paddle_graph_sha256": digest(source),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--all-failures",
        action="store_true",
        help="Trace all previously failed cases, not only the first",
    )
    parser.add_argument("--batch-size", type=int, default=32, choices=range(8, 65), metavar="8..64")
    args = parser.parse_args()
    import numpy as np
    import onnx
    import onnxruntime as ort
    import paddle
    from export_parity import normalized_image

    sys.path.insert(0, str(ROOT / "ml/training/ocr"))
    from model_card import describe
    from run_identity import validate_inputs

    run, output = args.run.resolve(strict=True), args.output.resolve()
    if not output.is_relative_to(ROOT / ".local/runs") or output.exists():
        parser.error("Use a new private run directory; previous evidence is immutable")
    if paddle.__version__ != "3.3.1" or ort.__version__ != "1.22.0":
        raise ValueError("Operation tracing requires pinned Paddle 3.3.1 / ORT 1.22.0")
    settings = json.loads((run / "settings.json").read_text())
    dataset_path = Path(settings["dataset"])
    dataset, identity_verification = validate_inputs(run)
    describe(run, dataset)
    print(
        f"Validated {len(dataset['samples'])} dataset records and training lineage; "
        f"dataset SHA256 {digest(dataset_path)}",
        flush=True,
    )
    prior = json.loads((run / "deployment/parity.json").read_text())
    cases = [r for r in prior["cases"] if not r["allclose"] or not r["same_tokens"]]
    if not cases:
        raise ValueError("No failed cases to diagnose")
    if not args.all_failures:
        cases = cases[:1]
    source = run / "deployment/paddle/inference.json"
    weights = source.with_suffix(".pdiparams")
    artifact = run / "deployment/recognizer.onnx"
    sources = {
        str(p): digest(p)
        for p in [
            source,
            weights,
            artifact,
            run / "deployment/parity.json",
            run / "deployment/export.json",
            run / "selected.pdparams",
            run / "selection.json",
            run / "settings.json",
            run / "identity.json",
            run / "export.yml",
            dataset_path,
            Path(__file__),
            Path(__file__).with_name("export_parity.py"),
        ]
    }
    original = json.loads(source.read_text())
    graph = onnx.load(artifact)
    _, aligned, missing = instrument_pir(original, {v for n in graph.graph.node for v in n.output})
    output.mkdir(parents=True, mode=0o700)
    options = ort.SessionOptions()
    options.intra_op_num_threads, options.inter_op_num_threads = 2, 1
    # Intermediate fetches change optimization opportunities. Disable graph
    # rewrites for diagnosis only, and retain uninstrumented control outputs.
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_DISABLE_ALL
    options.log_severity_level = 3
    control = ort.InferenceSession(
        str(artifact), sess_options=options, providers=["CPUExecutionProvider"]
    )
    paddle.set_device("cpu")
    baseline = paddle.jit.load(str(source.with_suffix("")))
    baseline.eval()
    report = {
        "schema_version": 1,
        "kind": "ocr-operation-parity-diagnostic",
        "diagnostic": True,
        "qualified": False,
        "status": "running",
        "paddle": paddle.__version__,
        "onnxruntime": ort.__version__,
        "onnx": onnx.__version__,
        "rtol": 1e-3,
        "atol": 1e-5,
        "graph_optimization": str(options.graph_optimization_level),
        "source_sha256": digest(Path(__file__)),
        "normalization_source_sha256": digest(Path(__file__).with_name("export_parity.py")),
        "sources": sources,
        "dataset_validation": {
            "passed": True,
            "records": len(dataset["samples"]),
            "kind": dataset["kind"],
            "dataset_sha256": digest(dataset_path),
            "training_lineage_verified": True,
            "identity_verification": identity_verification,
        },
        "aligned_outputs": len(aligned),
        "unmapped_float_outputs": missing,
        "instrumentation": "PIR v4 copied with additional fetches; original operators and parameters preserved",
        "batch_size": args.batch_size,
        "max_fetched_tensor_bytes": 0,
        "batches": [],
        "cases": [
            {"id": c["id"], "width": c["width"], "operations": [], "controls": []} for c in cases
        ],
    }
    records = {r["id"]: r for r in dataset["samples"]}
    for start in range(0, len(aligned), args.batch_size):
        selected = aligned[start : start + args.batch_size]
        names = {item["onnx_name"] for item in selected}
        copied, batch, _ = instrument_pir(original, names)
        # These are reproducible diagnostic intermediates, not a deployment export.
        # Retain hashes; discard each batch graph after collecting its evidence.
        with tempfile.TemporaryDirectory(prefix=".batch-", dir=output) as temporary:
            folder = Path(temporary)
            (folder / "inference.json").write_text(json.dumps(copied))
            shutil.copyfile(weights, folder / "inference.pdiparams")
            observed = copy.deepcopy(graph)
            for entry in batch:
                observed.graph.output.append(
                    onnx.helper.make_tensor_value_info(
                        entry["onnx_name"], onnx.TensorProto.FLOAT, None
                    )
                )
            observed_path = folder / "instrumented.onnx"
            onnx.save(observed, observed_path)
            report["batches"].append(
                {
                    "start": start,
                    "count": len(batch),
                    "intermediates_retained": False,
                    "paddle_graph_sha256": digest(folder / "inference.json"),
                    "onnx_graph_sha256": digest(observed_path),
                }
            )
            session = ort.InferenceSession(
                str(observed_path), sess_options=options, providers=["CPUExecutionProvider"]
            )
            model = paddle.jit.load(str(folder / "inference"))
            model.eval()
            with paddle.no_grad():
                for index, case in enumerate(cases):
                    result = report["cases"][index]
                    record = records[case["id"]]
                    path = dataset_path.parent / record["image"]
                    if digest(path) != record["image_sha256"]:
                        raise ValueError("Diagnostic pixels changed")
                    pixels = normalized_image(path, case["width"])
                    expected = [v.numpy() for v in model(paddle.to_tensor(pixels))]
                    actual = session.run(None, {session.get_inputs()[0].name: pixels})
                    if len(expected) != len(batch) + 1 or len(actual) != len(expected):
                        raise ValueError("Intermediate output alignment changed")
                    report["max_fetched_tensor_bytes"] = max(
                        report["max_fetched_tensor_bytes"],
                        sum(v.nbytes for v in [*expected, *actual]),
                    )
                    rows = [
                        {
                            "program_index": item["program_index"],
                            "operation": item["operation"],
                            "onnx_name": item["onnx_name"],
                            **compare(a, b),
                        }
                        for item, a, b in zip(batch, expected[1:], actual[1:], strict=True)
                    ]
                    result["operations"].extend(rows)
                    result["image_sha256"] = record["image_sha256"]
                    result["input_sha256"] = hashlib.sha256(pixels.tobytes()).hexdigest()
                    result["controls"].append(
                        {
                            "batch_start": start,
                            "instrumented_final": {
                                **compare(expected[0], actual[0]),
                                "same_tokens": bool(
                                    np.array_equal(expected[0].argmax(-1), actual[0].argmax(-1))
                                ),
                            },
                            "paddle": compare(
                                baseline(paddle.to_tensor(pixels)).numpy(), expected[0]
                            ),
                            "onnx": compare(
                                control.run(None, {control.get_inputs()[0].name: pixels})[0],
                                actual[0],
                            ),
                        }
                    )
                    first = first_differences(result["operations"])["first_bit_difference"]
                    if index == 0 and first and "isolated_first_difference" not in result:
                        result["isolated_first_difference"] = isolate_convolution(
                            output, first, batch, expected, pixels, source, graph, model, options
                        )
                    del expected, actual
            del model, session, observed
            gc.collect()
        print(
            f"Traced {min(start + args.batch_size, len(aligned))}/{len(aligned)} outputs over {len(cases)} cases",
            flush=True,
        )
    for result in report["cases"]:
        result.update(first_differences(result["operations"]))
        result["instrumentation_preserves_outputs"] = all(
            control[provider]["bitwise_equal"]
            for control in result["controls"]
            for provider in ["paddle", "onnx"]
        )
    report["instrumentation_preserves_outputs"] = all(
        result["instrumentation_preserves_outputs"] for result in report["cases"]
    )
    report["host_peak_rss_bytes"] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss * (
        1 if sys.platform == "darwin" else 1024
    )
    if sources != {p: digest(Path(p)) for p in sources}:
        raise ValueError("Historical evidence changed during tracing")
    report["status"] = (
        "diagnosed-not-qualified"
        if report["instrumentation_preserves_outputs"]
        else "instrumentation-perturbs-output"
    )
    with (output / "report.json").open("x") as stream:
        stream.write(json.dumps(report, indent=2, allow_nan=False) + "\n")
    print("Operation trace complete; no deployment artifact or acceptance threshold was changed")


if __name__ == "__main__":
    for variable in ["OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"]:
        os.environ.setdefault(variable, "2")
    main()
