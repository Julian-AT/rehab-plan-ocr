"""Verify the official trainable checkpoint against the unchanged iOS dictionary.

This is a compatibility check, not a training or accuracy result. No private
images are read. Run in the independently locked OCR environment.
"""

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, default=ROOT / ".local/upstream/PaddleOCR")
    parser.add_argument(
        "--weights",
        type=Path,
        default=ROOT / ".local/models/ocr/PP-OCRv6_small_rec_pretrained.pdparams",
    )
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    pin = json.loads((ROOT / "ml/registry/ocr-base.json").read_text())
    revision = subprocess.check_output(
        ["git", "-C", str(args.upstream), "rev-parse", "HEAD"], text=True
    ).strip()
    if revision != pin["revision"]:
        raise ValueError("PaddleOCR checkout does not match the registry revision")
    if sha(args.weights) != pin["checkpoint_sha256"]:
        raise ValueError("Training checkpoint checksum mismatch")
    dictionary_path = args.upstream / "ppocr/utils/dict/ppocrv6_dict.txt"
    characters = dictionary_path.read_text().splitlines()
    deployment_dictionary = json.dumps([""] + characters + [" "], ensure_ascii=False).encode()
    if hashlib.sha256(deployment_dictionary).hexdigest() != pin["deployment_dictionary_sha256"]:
        raise ValueError("Training dictionary differs from the shipping CTC dictionary")
    import paddle
    import yaml

    sys.path.insert(0, str(args.upstream.resolve()))
    from ppocr.modeling.architectures import build_model

    paddle.set_device("cpu")
    config_path = args.upstream / pin["configuration"]
    config = yaml.safe_load(config_path.read_text())
    config["Architecture"]["Head"]["out_channels_list"] = {
        "CTCLabelDecode": len(characters) + 2,
        "NRTRLabelDecode": len(characters) + 5,
    }
    model = build_model(config["Architecture"])
    actual = paddle.load(str(args.weights))
    expected = model.state_dict()
    missing = sorted(set(expected) - set(actual))
    unexpected = sorted(set(actual) - set(expected))
    mismatches = [
        key
        for key in expected.keys() & actual.keys()
        if list(expected[key].shape) != list(actual[key].shape)
    ]
    if missing or unexpected or mismatches:
        raise ValueError(
            json.dumps({"missing": missing, "unexpected": unexpected, "shape": mismatches})
        )
    model.set_state_dict(actual)
    report = {
        "schema_version": 1,
        "kind": "checkpoint-compatibility",
        "trained": False,
        "model": pin["model"],
        "upstream_revision": revision,
        "checkpoint_sha256": sha(args.weights),
        "configuration_sha256": sha(config_path),
        "dictionary_sha256": pin["deployment_dictionary_sha256"],
        "environment_sha256": sha(Path(__file__).with_name("uv.lock")),
        "paddle_version": paddle.__version__,
        "parameter_tensors": len(expected),
        "parameters": sum(value.numel().item() for value in expected.values()),
        "missing": missing,
        "unexpected": unexpected,
        "shape_mismatches": mismatches,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
