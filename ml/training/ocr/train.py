"""PP-OCRv6 Small adaptation with atomic epoch checkpoints and validation stopping.

CPU only, matching dictionary and architecture. Interrupted epochs replay from the
last completed epoch, with the same epoch seed, optimizer and fixed learning rate.
There is no time cap. These crop metrics never qualify an end-to-end app model.
"""

import argparse
import copy
import fcntl
import hashlib
import importlib.metadata
import json
import math
import os
import platform
import random
import subprocess
import sys
import time
import uuid
from collections import defaultdict
from pathlib import Path

from contract import CRITICAL, advance, field_name, sha, validate_dataset, write
from preflight import ROOT

sys.path.insert(0, str(ROOT))
from ml.training.storage import checkpoint_peak, require_storage  # noqa: E402

UPSTREAM = ROOT / ".local/upstream/PaddleOCR"
DICTIONARY = UPSTREAM / "ppocr/utils/dict/ppocrv6_dict.txt"
WEIGHTS = ROOT / ".local/models/ocr/PP-OCRv6_small_rec_pretrained.pdparams"


def lineage(dataset_path):
    return {
        "dataset_sha256": sha(dataset_path),
        "registry_sha256": sha(ROOT / "ml/registry/ocr-base.json"),
        "environment_sha256": sha(Path(__file__).with_name("uv.lock")),
        "packages": {
            name: importlib.metadata.version(name)
            for name in ["paddlepaddle", "numpy", "pillow", "pyyaml", "rapidfuzz"]
        },
        "source_sha256": {
            name: sha(Path(__file__).with_name(name))
            for name in ["train.py", "contract.py", "prepare.py"]
        },
        "reference_tool_sha256": sha(ROOT / "ml/data/annotation/reference-data.py"),
        "privacy_tool_sha256": sha(ROOT / "ml/data/annotation/privacy.py"),
        "compatibility_tool_sha256": sha(Path(__file__).with_name("run_identity.py")),
        "storage_tool_sha256": sha(ROOT / "ml/training/storage.py"),
        "python": sys.version,
        "platform": platform.platform(),
    }


def current_review(dataset, path):
    if dataset["kind"] != "approved-reference-crops":
        return
    from prepare import reference_module

    reference = reference_module()
    root = Path(dataset["source_root"])
    exported = json.loads((path.parent / "references/manifest.json").read_text())
    refs = []
    for source, expected in exported["reference_hashes"].items():
        ref = json.loads((root / "labels/provisional" / (source + ".json")).read_text())
        reference.approved(ref)
        if reference.reference_hash(ref) != expected:
            raise ValueError("Live human reference changed; prepare a new dataset")
        refs.append(ref)
    privacy = reference.validate_privacy(root, refs)
    if exported.get("privacy_review") != privacy or any(
        row.get("privacy_review_sha256") != privacy["review_file_sha256"]
        for row in dataset["samples"]
    ):
        raise ValueError("Privacy or purpose review changed; prepare a new dataset")
    checked = reference.reviewed_crops(root, refs)
    if any(row["crop_review_hash"] != sha(root / "crop-review.json") for row in dataset["samples"]):
        raise ValueError("Crop review changed; prepare a new dataset")
    if reference.grouping(refs) != json.loads((root / "split.json").read_text()):
        raise ValueError("Live source grouping changed")
    for name, expected in exported["files"].items():
        if sha(path.parent / "references" / name) != expected:
            raise ValueError("Prepared reference export changed")
    records = [
        json.loads(line)
        for line in (path.parent / "references/recognition.jsonl").read_text().splitlines()
    ]
    expected = {row["id"] + "-" + row["line_id"]: row for row in records}
    if set(expected) != {row["id"] for row in dataset["samples"]}:
        raise ValueError("Prepared samples differ from the complete approved export")
    lines = {line["id"]: line for ref in refs for line in ref["lines"]}
    for row in dataset["samples"]:
        record = expected[row["id"]]
        if record["line_id"] not in checked or any(
            row[key] != record[key]
            for key in ["text", "partition", "group", "reference_hash", "privacy_review_sha256"]
        ):
            raise ValueError("Training label or partition differs from the reviewed reference")
        if (
            row["source_sha256"] != record["source_hash"]
            or row["field"] != field_name(lines[record["line_id"]]["field"])
            or row["variant"] != record["name"]
        ):
            raise ValueError("Training field or source differs from the reviewed reference")


def summary(rows):
    groups = defaultdict(list)
    critical = [row for row in rows if row["field"] in CRITICAL]
    for row in rows:
        groups[row["group"]].append(row["correct"])
    return {
        "samples": len(rows),
        "independent_groups": len(groups),
        "exact": sum(row["correct"] for row in rows),
        "critical_samples": len(critical),
        "critical_errors": sum(not row["correct"] for row in critical),
        "group_mean_error": sum(1 - sum(values) / len(values) for values in groups.values())
        / len(groups)
        if groups
        else 0,
        "character_errors": sum(row["character_errors"] for row in rows),
        "reference_characters": sum(len(row["expected"]) for row in rows),
    }


def checkpoint(run, epoch, model, optimizer, state, metrics):
    import paddle

    require_storage(
        ROOT,
        run,
        4,
        checkpoint_peak(
            model.state_dict(),
            optimizer.state_dict(),
            trainable=[
                parameter for parameter in model.parameters() if not parameter.stop_gradient
            ],
        ),
    )
    parent = run / "checkpoints"
    parent.mkdir(exist_ok=True)
    temporary = parent / (".incomplete-" + uuid.uuid4().hex)
    temporary.mkdir()
    # One file contains weights and optimizer; publication is one directory rename.
    paddle.save(
        {"model": model.state_dict(), "optimizer": optimizer.state_dict()},
        str(temporary / "training.pdstate"),
    )
    with (temporary / "training.pdstate").open("rb") as stream:
        os.fsync(stream.fileno())
    write(
        temporary / "checkpoint.json",
        {
            "epoch": epoch,
            "state": state,
            "metrics": metrics,
            "training_sha256": sha(temporary / "training.pdstate"),
            "run_identity": sha(run / "identity.json"),
            "baseline_sha256": sha(run / "baseline.json"),
        },
    )
    temporary.rename(parent / f"epoch-{epoch:04d}")
    descriptor = os.open(parent, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def latest_checkpoint(run):
    choices = sorted((run / "checkpoints").glob("epoch-*"))
    if not choices:
        return None, None
    path = choices[-1]
    receipt = json.loads((path / "checkpoint.json").read_text())
    if receipt["run_identity"] != sha(run / "identity.json") or receipt["training_sha256"] != sha(
        path / "training.pdstate"
    ):
        raise ValueError("Checkpoint identity or optimizer/weights checksum mismatch")
    if receipt.get("baseline_sha256") and receipt["baseline_sha256"] != sha(run / "baseline.json"):
        raise ValueError("Baseline evidence changed since the checkpoint")
    return path, receipt


def execute(run, pause_after_epoch=None):
    require_storage(ROOT, run, 4)
    import numpy as np
    import paddle
    import yaml
    from rapidfuzz.distance import Levenshtein

    sys.path.insert(0, str(UPSTREAM))
    from ppocr.data.imaug import create_operators, transform
    from ppocr.losses import build_loss
    from ppocr.modeling.architectures import build_model
    from ppocr.postprocess import build_post_process

    config = json.loads((run / "settings.json").read_text())
    dataset_path = Path(config["dataset"])
    from run_identity import validate_inputs

    dataset, identity_proof = validate_inputs(run)
    if identity_proof["mode"] != "current":
        raise ValueError("Use the archived engine for an original synthetic run")
    subprocess.run(
        [sys.executable, str(Path(__file__).with_name("restore.py")), "--offline"], check=True
    )
    chars = DICTIONARY.read_text().splitlines()
    pin = json.loads((ROOT / "ml/registry/ocr-base.json").read_text())
    actual_dictionary = hashlib.sha256(
        json.dumps([""] + chars + [" "], ensure_ascii=False).encode()
    ).hexdigest()
    if actual_dictionary != pin["deployment_dictionary_sha256"]:
        raise ValueError("Dictionary differs from the deployed recognizer")
    paddle.set_device("cpu")
    paddle.seed(config["seed"])
    architecture = yaml.safe_load((UPSTREAM / pin["configuration"]).read_text())
    maximum = max(len(row["text"]) for row in dataset["samples"]) + 2
    # NRTR requires space for BOS and EOS; CTC labels are never truncated.
    architecture["Global"].update(
        use_gpu=False,
        distributed=False,
        character_dict_path=str(DICTIONARY),
        max_text_length=maximum,
    )
    architecture["Architecture"]["Head"]["out_channels_list"] = {
        "CTCLabelDecode": len(chars) + 2,
        "NRTRLabelDecode": len(chars) + 5,
    }
    for head in architecture["Architecture"]["Head"]["head_list"]:
        if "NRTRHead" in head:
            head["NRTRHead"]["max_text_length"] = maximum
    write(run / "architecture.json", architecture)
    (run / "export.yml").write_text(yaml.safe_dump(architecture, allow_unicode=True))
    model = build_model(copy.deepcopy(architecture["Architecture"]))
    weights = paddle.load(str(WEIGHTS))
    if set(weights) != set(model.state_dict()) or any(
        list(value.shape) != list(model.state_dict()[name].shape) for name, value in weights.items()
    ):
        raise ValueError("Label-length configuration changed the pinned checkpoint architecture")
    model.set_state_dict(weights)
    del weights
    if config["mode"] == "frozen-backbone":
        for parameter in model.backbone.parameters():
            parameter.stop_gradient = True
    optimizer = paddle.optimizer.Adam(
        learning_rate=config["learning_rate"],
        beta1=0.9,
        beta2=0.999,
        parameters=[p for p in model.parameters() if not p.stop_gradient],
        weight_decay=paddle.regularizer.L2Decay(3e-5),
    )
    loss_fn = build_loss(copy.deepcopy(architecture["Loss"]))
    decoder = build_post_process(architecture["PostProcess"], architecture["Global"])
    operations = create_operators(
        [
            {"DecodeImage": {"img_mode": "BGR", "channel_first": False}},
            {"MultiLabelEncode": {"gtc_encode": "NRTRLabelEncode"}},
            {"RecResizeImg": {"image_shape": [3, 48, config["width"]]}},
            {
                "KeepKeys": {
                    "keep_keys": ["image", "label_ctc", "label_gtc", "length", "valid_ratio"]
                }
            },
        ],
        architecture["Global"],
    )
    partitions = {
        part: [row for row in dataset["samples"] if row["partition"] == part]
        for part in ["train", "validation"]
    }

    def batches(rows):
        for offset in range(0, len(rows), config["batch_size"]):
            samples = rows[offset : offset + config["batch_size"]]
            processed = []
            for row in samples:
                path = dataset_path.parent / row["image"]
                if sha(path) != row["image_sha256"]:
                    raise ValueError("Training pixels changed during run")
                result = transform({"image": path.read_bytes(), "label": row["text"]}, operations)
                if result is None or int(result[3]) != len(row["text"]):
                    raise ValueError("Label encoder dropped or truncated a verified target")
                processed.append(result)
            yield (
                samples,
                [
                    paddle.to_tensor(np.stack([entry[index] for entry in processed]))
                    for index in range(5)
                ],
            )

    def evaluate():
        model.eval()
        results = []
        with paddle.no_grad():
            for samples, batch in batches(partitions["validation"]):
                predictions = decoder(model(batch[0]))
                for row, (prediction, confidence) in zip(samples, predictions, strict=True):
                    results.append(
                        {
                            "id": row["id"],
                            "group": row["group"],
                            "field": row["field"],
                            "variant": row.get("variant", "original"),
                            "expected": row["text"],
                            "predicted": prediction,
                            "confidence": float(confidence),
                            "correct": prediction == row["text"],
                            "character_errors": Levenshtein.distance(prediction, row["text"]),
                        }
                    )
        return {
            "overall": summary(results),
            "originals": summary([r for r in results if r["variant"] == "original"]),
            "robustness": summary([r for r in results if r["variant"] != "original"]),
            "rows": results,
        }

    # CTC needs extra time steps for repeated adjacent characters.
    model.eval()
    with paddle.no_grad():
        steps = int(model(paddle.zeros([1, 3, 48, config["width"]])).shape[1])
    required = max(
        len(r["text"]) + sum(a == b for a, b in zip(r["text"], r["text"][1:]))
        for r in dataset["samples"]
    )
    if required > steps:
        raise ValueError(
            f"CTC needs {required} time steps, configured width gives {steps}; targets were not truncated"
        )
    path, receipt = latest_checkpoint(run)
    if receipt:
        saved = paddle.load(str(path / "training.pdstate"))
        model.set_state_dict(saved["model"])
        optimizer.set_state_dict(saved["optimizer"])
        state = receipt["state"]
        del saved
    else:
        baseline = evaluate()
        write(run / "baseline.json", baseline)
        state = {
            "epoch": 0,
            "steps": 0,
            "best_score": None,
            "best_epoch": None,
            "stale_epochs": 0,
            "stopped": False,
        }
    base_rows = {r["id"]: r for r in json.loads((run / "baseline.json").read_text())["rows"]}
    for epoch in range(state["epoch"] + 1, config["max_epochs"] + 1):
        if state["stopped"]:
            break
        require_storage(
            ROOT,
            run,
            4,
            checkpoint_peak(
                model.state_dict(),
                optimizer.state_dict(),
                trainable=[p for p in model.parameters() if not p.stop_gradient],
            ),
        )
        epoch_seed = config["seed"] + epoch
        random.seed(epoch_seed)
        np.random.seed(epoch_seed)
        paddle.seed(epoch_seed)
        rows = list(partitions["train"])
        random.shuffle(rows)
        model.train()
        if config["mode"] == "frozen-backbone":
            model.backbone.eval()  # Freeze batch-normalization buffers as well as weights.
        started, loss_sum, count = time.monotonic(), 0.0, 0
        for samples, batch in batches(rows):
            predictions = model(batch[0], data=batch[1:])
            loss = loss_fn(predictions, batch)["loss"]
            value = float(loss.item())
            if not math.isfinite(value):
                raise ValueError("Nonfinite training loss; last complete checkpoint preserved")
            loss.backward()
            optimizer.step()
            optimizer.clear_grad()
            loss_sum += value * len(samples)
            count += len(samples)
            state["steps"] += 1
            print(json.dumps({"epoch": epoch, "step": state["steps"], "loss": value}), flush=True)
        metrics = evaluate()
        metrics.update(
            train_loss=loss_sum / count,
            elapsed_seconds=time.monotonic() - started,
            new_critical_errors=[
                r["id"]
                for r in metrics["rows"]
                if r["field"] in CRITICAL and not r["correct"] and base_rows[r["id"]]["correct"]
            ],
        )
        state = advance(state, metrics["overall"], epoch, config["patience"])
        checkpoint(run, epoch, model, optimizer, state, metrics)
        write(run / "progress.json", state | {"status": "running", "qualified": False})
        print(
            json.dumps(
                {
                    "epoch": epoch,
                    "steps": state["steps"],
                    "validation": metrics["overall"],
                    "best_epoch": state["best_epoch"],
                }
            ),
            flush=True,
        )
        if (
            pause_after_epoch
            and epoch >= pause_after_epoch
            and not state["stopped"]
            and epoch < config["max_epochs"]
        ):
            write(run / "progress.json", state | {"status": "paused", "qualified": False})
            return
    write(
        run / "progress.json",
        state
        | {
            "status": "validation-stopped" if state["stopped"] else "epoch-limit",
            "qualified": False,
        },
    )
    best = run / "checkpoints" / f"epoch-{state['best_epoch']:04d}"
    selected = json.loads((best / "checkpoint.json").read_text())
    if selected["training_sha256"] != sha(best / "training.pdstate"):
        raise ValueError("Selected checkpoint checksum changed")
    require_storage(ROOT, run, 4, checkpoint_peak(model.state_dict(), {}))
    paddle.save(
        paddle.load(str(best / "training.pdstate"))["model"], str(run / "selected.pdparams")
    )
    write(
        run / "selection.json",
        {
            "epoch": state["best_epoch"],
            "sha256": sha(run / "selected.pdparams"),
            "export_config_sha256": sha(run / "export.yml"),
            "metrics": selected["metrics"],
            "qualified": False,
            "requires": [
                "end-to-end-critical-field-evaluation",
                "onnx-parity",
                "device-evaluation",
            ],
        },
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    start = commands.add_parser("start")
    resume = commands.add_parser("resume")
    for command in [start, resume]:
        command.add_argument("--run", type=Path, required=True)
        command.add_argument("--pause-after-epoch", type=int)
    start.add_argument("--dataset", type=Path, required=True)
    start.add_argument("--mode", choices=["frozen-backbone", "full"], default="frozen-backbone")
    start.add_argument("--learning-rate", type=float)
    start.add_argument("--max-epochs", type=int, default=100)
    start.add_argument("--patience", type=int, default=5)
    start.add_argument("--batch-size", type=int, default=2)
    start.add_argument("--width", type=int, choices=[320, 640, 960], default=320)
    start.add_argument("--seed", type=int, default=20260917)
    args = parser.parse_args()
    run = args.run.resolve()
    if not run.is_relative_to(ROOT / ".local/runs"):
        parser.error("Training runs must remain below .local/runs")
    if args.action == "start":
        if not args.dataset or min(args.max_epochs, args.patience, args.batch_size) < 1:
            parser.error("A dataset and positive epoch, patience and batch settings are required")
        lr = (
            args.learning_rate
            if args.learning_rate is not None
            else (1e-5 if args.mode == "full" else 1e-4)
        )
        if not math.isfinite(lr) or lr <= 0:
            parser.error("Learning rate must be finite and positive")
        dataset = args.dataset.resolve(strict=True)
        validate_dataset(dataset, DICTIONARY.read_text().splitlines())
        run.mkdir(parents=True, exist_ok=False)
        settings = {
            "dataset": str(dataset),
            "mode": args.mode,
            "learning_rate": lr,
            **{
                key: getattr(args, key)
                for key in ["max_epochs", "patience", "batch_size", "width", "seed"]
            },
        }
        write(run / "settings.json", settings)
        write(
            run / "identity.json",
            {"settings_sha256": sha(run / "settings.json"), "lineage": lineage(dataset)},
        )
    with (run / "training.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            from run_identity import resume_legacy, verify

            if verify(run)["mode"] == "archived-synthetic-v1":
                resume_legacy(run, args.pause_after_epoch)
            else:
                execute(run, args.pause_after_epoch)
        except BaseException:
            write(
                run / "last-interruption.json",
                {
                    "at": time.time(),
                    "recovery": "Replay from the last completed atomic epoch checkpoint",
                },
            )
            raise


if __name__ == "__main__":
    os.environ.setdefault("OMP_NUM_THREADS", "2")
    os.environ.setdefault("OPENBLAS_NUM_THREADS", "2")
    os.environ.setdefault("MKL_NUM_THREADS", "2")
    main()
