"""Compare the trained Paddle CTC output with the shipping ONNX Runtime version."""

import argparse
import hashlib
import json
import sys
from pathlib import Path

import cv2
import numpy as np
import onnxruntime as ort
import paddle
import yaml
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def normalized_image(path, width):
    image = np.asarray(Image.open(path).convert("RGB"))[:, :, ::-1]
    resized_width = min(width, int(np.ceil(48 * image.shape[1] / image.shape[0])))
    resized = cv2.resize(image, (resized_width, 48)).astype("float32").transpose(2, 0, 1)
    padded = np.zeros((1, 3, 48, width), dtype="float32")
    padded[0, :, :, :resized_width] = (resized / 255.0 - 0.5) / 0.5
    return padded


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--onnx", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument(
        "--baseline",
        action="store_true",
        help="Diagnose pinned pretrained weights against the shipping small recognizer",
    )
    parser.add_argument(
        "--graph-optimization", choices=["shipping", "disabled"], default="shipping"
    )
    parser.add_argument(
        "--failures-from", type=Path, help="Diagnose only failed cases in a retained parity report"
    )
    args = parser.parse_args()
    if ort.__version__ != "1.22.0":
        raise ValueError("Parity must use the pinned shipping runtime, ONNX Runtime 1.22.0")
    run = args.run.resolve()
    report_path = args.report or run / "parity.json"
    if report_path.exists():
        raise ValueError("Preserve prior parity evidence; select a new report path")
    identity_verification = None
    if (run / "settings.json").exists():
        settings = json.loads((run / "settings.json").read_text())
        dataset_path = Path(settings["dataset"])
        sys.path.insert(0, str(ROOT / "ml/training/ocr"))
        from run_identity import validate_inputs

        dataset, identity_verification = validate_inputs(run)
        records = [dict(row, path=dataset_path.parent / row["image"]) for row in dataset["samples"]]
        checkpoint = run / "selected.pdparams"
        selected = json.loads((run / "selection.json").read_text())
        if digest(checkpoint) != selected["sha256"]:
            raise ValueError("Selected checkpoint changed")
        config_path = run / "export.yml"
        if digest(config_path) != selected["export_config_sha256"]:
            raise ValueError("Selected export configuration changed")
        widths = sorted({320, 640, settings["width"]})
    else:
        config_path = run / "config.yml"
        checkpoint = run / "checkpoints/latest.pdparams"
        records = [json.loads(line) for line in (run / "samples.jsonl").read_text().splitlines()]
        records = [dict(row, path=run / f"{row['id']}.png") for row in records]
        widths = [320, 640]
    model_path = args.onnx or run / "recognizer.onnx"
    baseline_registry = None
    if args.baseline:
        if not args.report or not (run / "settings.json").exists():
            parser.error("Baseline diagnosis requires a prepared run and an explicit new --report")
        baseline_registry = ROOT / "ml/registry/ocr-base.json"
        base = json.loads(baseline_registry.read_text())
        lock = json.loads((ROOT / "ml/registry/runtime/small.lock.json").read_text())
        pinned = next(row for row in lock["files"] if row["path"] == "rec-inference.onnx")
        checkpoint = ROOT / ".local/models/ocr/PP-OCRv6_small_rec_pretrained.pdparams"
        model_path = args.onnx or ROOT / ".local/models/runtime/small/rec-inference.onnx"
        if (
            digest(checkpoint) != base["checkpoint_sha256"]
            or digest(model_path) != pinned["sha256"]
            or base["deployment_dictionary_sha256"] != lock["dictionary_sha256"]
        ):
            raise ValueError(
                "Pretrained checkpoint, shipping recognizer or dictionary identity changed"
            )
    selected_cases = None
    if args.failures_from:
        previous = json.loads(args.failures_from.read_text())
        if previous["artifact_sha256"] != digest(model_path) or previous[
            "checkpoint_sha256"
        ] != digest(checkpoint):
            raise ValueError("Diagnostic cases belong to different model weights")
        selected_cases = {
            (r["id"], r["width"])
            for r in previous["cases"]
            if not r["allclose"] or not r["same_tokens"]
        }
        available = {(r["id"], w) for r in records for w in widths}
        if not selected_cases or not selected_cases.issubset(available):
            raise ValueError("No matching failed parity cases to diagnose")
    config = yaml.safe_load(config_path.read_text())
    characters = Path(config["Global"]["character_dict_path"]).read_text().splitlines()
    config["Architecture"]["Head"]["out_channels_list"] = {
        "CTCLabelDecode": len(characters) + 2,
        "NRTRLabelDecode": len(characters) + 5,
    }
    sys.path.insert(0, str(ROOT / ".local/upstream/PaddleOCR"))
    from ppocr.modeling.architectures import build_model

    paddle.set_device("cpu")
    model = build_model(config["Architecture"])
    model.set_state_dict(paddle.load(str(checkpoint)))
    model.eval()
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    if args.graph_optimization == "disabled":
        options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_DISABLE_ALL
    session = ort.InferenceSession(
        str(model_path), sess_options=options, providers=["CPUExecutionProvider"]
    )
    rows = []
    with paddle.no_grad():
        for record in records:
            if digest(record["path"]) != record["image_sha256"]:
                raise ValueError("Parity pixels changed since dataset preparation")
            # Both common and longer crops exercise dynamic width through export.
            for width in widths:
                if selected_cases is not None and (record["id"], width) not in selected_cases:
                    continue
                image = normalized_image(record["path"], width)
                expected = model(paddle.to_tensor(image)).numpy()
                actual = session.run(None, {session.get_inputs()[0].name: image})[0]
                equal_shape = expected.shape == actual.shape
                error = float(np.max(np.abs(expected - actual))) if equal_shape else None
                close = equal_shape and bool(np.allclose(expected, actual, rtol=1e-3, atol=1e-5))
                same_tokens = equal_shape and bool(
                    np.array_equal(expected.argmax(-1), actual.argmax(-1))
                )
                rows.append(
                    {
                        "id": record["id"],
                        "width": width,
                        "shape": list(actual.shape),
                        "max_absolute_error": error,
                        "allclose": close,
                        "same_tokens": same_tokens,
                    }
                )
    passed = bool(rows) and all(row["allclose"] and row["same_tokens"] for row in rows)
    report = {
        "identity_verification": identity_verification,
        "schema_version": 1,
        "kind": "paddle-onnx-export-parity",
        "passed": passed,
        "onnxruntime": ort.__version__,
        "provider": "CPUExecutionProvider",
        "graph_optimization": str(options.graph_optimization_level),
        "diagnostic": args.baseline
        or args.graph_optimization != "shipping"
        or selected_cases is not None,
        "checkpoint_role": "pretrained-baseline" if args.baseline else "selected",
        "baseline_registry_sha256": digest(baseline_registry) if baseline_registry else None,
        "subset_source_sha256": digest(args.failures_from) if args.failures_from else None,
        "paddle": paddle.__version__,
        "artifact_sha256": digest(model_path),
        "checkpoint_sha256": digest(checkpoint),
        "rtol": 1e-3,
        "atol": 1e-5,
        "cases": rows,
        "quality_qualification": False,
        "physical_ios_verified": False,
    }
    with report_path.open("x") as stream:
        stream.write(json.dumps(report, indent=2) + "\n")
    print(
        f"Export parity: {sum(row['allclose'] and row['same_tokens'] for row in rows)}/{len(rows)} cases"
    )
    if not passed:
        raise SystemExit("Export parity failed; artifact must not be promoted")


if __name__ == "__main__":
    main()
