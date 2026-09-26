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
    args = parser.parse_args()
    if ort.__version__ != "1.22.0":
        raise ValueError("Parity must use the pinned shipping runtime, ONNX Runtime 1.22.0")
    run = args.run.resolve()
    config = yaml.safe_load((run / "config.yml").read_text())
    characters = Path(config["Global"]["character_dict_path"]).read_text().splitlines()
    config["Architecture"]["Head"]["out_channels_list"] = {
        "CTCLabelDecode": len(characters) + 2,
        "NRTRLabelDecode": len(characters) + 5,
    }
    sys.path.insert(0, str(ROOT / ".local/upstream/PaddleOCR"))
    from ppocr.modeling.architectures import build_model

    paddle.set_device("cpu")
    model = build_model(config["Architecture"])
    model.set_state_dict(paddle.load(str(run / "checkpoints/latest.pdparams")))
    model.eval()
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(
        str(run / "recognizer.onnx"), sess_options=options, providers=["CPUExecutionProvider"]
    )
    rows = []
    records = [json.loads(line) for line in (run / "samples.jsonl").read_text().splitlines()]
    with paddle.no_grad():
        for record in records:
            # Both common and longer crops exercise dynamic width through export.
            for width in [320, 640]:
                image = normalized_image(run / f"{record['id']}.png", width)
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
    passed = all(row["allclose"] and row["same_tokens"] for row in rows)
    report = {
        "schema_version": 1,
        "kind": "paddle-onnx-export-parity",
        "passed": passed,
        "onnxruntime": ort.__version__,
        "provider": "CPUExecutionProvider",
        "paddle": paddle.__version__,
        "artifact_sha256": digest(run / "recognizer.onnx"),
        "checkpoint_sha256": digest(run / "checkpoints/latest.pdparams"),
        "rtol": 1e-3,
        "atol": 1e-5,
        "cases": rows,
        "quality_qualification": False,
        "physical_ios_verified": False,
    }
    (run / "parity.json").write_text(json.dumps(report, indent=2) + "\n")
    print(
        f"Export parity: {sum(row['allclose'] and row['same_tokens'] for row in rows)}/{len(rows)} cases"
    )
    if not passed:
        raise SystemExit("Export parity failed; artifact must not be promoted")


if __name__ == "__main__":
    main()
