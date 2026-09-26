"""Diagnose failed OCR parity across official reparameterization, static export and ONNX."""

import argparse
import copy
import json
import sys
from pathlib import Path

import numpy as np
import onnxruntime as ort
import paddle
import yaml
from export_parity import digest, normalized_image

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "ml/training/ocr"))
from contract import validate_dataset  # noqa: E402
from model_card import describe  # noqa: E402
from train import DICTIONARY, UPSTREAM, current_review, lineage  # noqa: E402


def compare(expected, actual):
    if expected.shape != actual.shape:
        return {"equal_shape": False, "allclose": False, "same_tokens": False}
    difference = np.abs(expected - actual)
    return {
        "equal_shape": True,
        "allclose": bool(np.allclose(expected, actual, rtol=1e-3, atol=1e-5)),
        "same_tokens": bool(np.array_equal(expected.argmax(-1), actual.argmax(-1))),
        "max_absolute_error": float(difference.max()),
        "failed_values": int(np.count_nonzero(difference > 1e-5 + 1e-3 * np.abs(actual))),
        "total_values": int(actual.size),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    run, output = args.run.resolve(strict=True), args.report.resolve()
    if not output.is_relative_to(ROOT / ".local") or output.exists():
        parser.error("Use a new report path below .local; prior evidence is preserved")
    if ort.__version__ != "1.22.0":
        raise ValueError("Use the pinned shipping ONNX Runtime 1.22.0")
    settings = json.loads((run / "settings.json").read_text())
    dataset_path = Path(settings["dataset"])
    if json.loads((run / "identity.json").read_text()) != {
        "settings_sha256": digest(run / "settings.json"),
        "lineage": lineage(dataset_path),
    }:
        raise ValueError("Run lineage changed")
    dataset = validate_dataset(dataset_path, DICTIONARY.read_text().splitlines())
    current_review(dataset, dataset_path)
    describe(run, dataset)  # Recheck completed selection, export, scores and every parity case.
    prior = json.loads((run / "deployment/parity.json").read_text())
    cases = [row for row in prior["cases"] if not row["allclose"] or not row["same_tokens"]]
    if not cases:
        raise ValueError("No failed deployment parity cases to diagnose")
    sources = [
        run / "selected.pdparams",
        run / "export.yml",
        run / "deployment/parity.json",
        run / "deployment/export.json",
        run / "deployment/recognizer.onnx",
        run / "deployment/paddle/inference.json",
        run / "deployment/paddle/inference.pdiparams",
    ]
    identities = {str(p.relative_to(run)): digest(p) for p in sources}
    sys.path.insert(0, str(UPSTREAM))
    from ppocr.modeling.architectures import build_model

    config = yaml.safe_load((run / "export.yml").read_text())
    paddle.set_device("cpu")
    dynamic = build_model(config["Architecture"])
    dynamic.set_state_dict(paddle.load(str(run / "selected.pdparams")))
    dynamic.eval()
    fused = copy.deepcopy(dynamic)
    # Same traversal as the pinned upstream dynamic_to_static export function.
    for layer in fused.sublayers():
        if hasattr(layer, "rep") and not getattr(layer, "is_repped", False):
            layer.rep()
    fused.eval()
    static = paddle.jit.load(str(run / "deployment/paddle/inference"))
    static.eval()
    options = ort.SessionOptions()
    options.intra_op_num_threads, options.inter_op_num_threads = 2, 1
    session = ort.InferenceSession(
        str(run / "deployment/recognizer.onnx"),
        sess_options=options,
        providers=["CPUExecutionProvider"],
    )
    report = {
        "schema_version": 1,
        "kind": "ocr-export-stage-diagnostic",
        "diagnostic": True,
        "qualified": False,
        "paddle": paddle.__version__,
        "onnxruntime": ort.__version__,
        "graph_optimization": str(options.graph_optimization_level),
        "source_sha256": digest(Path(__file__)),
        "normalization_source_sha256": digest(Path(__file__).with_name("export_parity.py")),
        "upstream_export_source_sha256": digest(UPSTREAM / "ppocr/utils/export_model.py"),
        "sources": identities,
        "rtol": 1e-3,
        "atol": 1e-5,
        "cases": [],
    }
    records = {row["id"]: row for row in dataset["samples"]}
    with paddle.no_grad():
        for case in cases:
            row = records[case["id"]]
            path = dataset_path.parent / row["image"]
            if digest(path) != row["image_sha256"]:
                raise ValueError("Diagnostic pixels changed")
            pixels = normalized_image(path, case["width"])
            outputs = {
                "dynamic": dynamic(paddle.to_tensor(pixels)).numpy(),
                "fused": fused(paddle.to_tensor(pixels)).numpy(),
                "static": static(paddle.to_tensor(pixels)).numpy(),
                "onnx": session.run(None, {session.get_inputs()[0].name: pixels})[0],
            }
            result = {"id": case["id"], "width": case["width"]}
            for left, right in [
                ("dynamic", "fused"),
                ("fused", "static"),
                ("static", "onnx"),
                ("dynamic", "onnx"),
            ]:
                result[f"{left}_{right}"] = compare(outputs[left], outputs[right])
            report["cases"].append(result)
    if identities != {str(p.relative_to(run)): digest(p) for p in sources}:
        raise ValueError("Source evidence changed during diagnosis")
    with output.open("x") as stream:
        stream.write(json.dumps(report, indent=2, allow_nan=False) + "\n")
    print(f"Diagnosed {len(cases)} failed cases; this report cannot qualify an artifact")


if __name__ == "__main__":
    main()
