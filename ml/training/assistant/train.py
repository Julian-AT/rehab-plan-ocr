"""Resumable offline Qwen3 LoRA training with grouped structured-intent validation.

Complete epochs are atomic checkpoints of adapters, Adam state and random state.
An interrupted epoch replays from its last checkpoint. No wall-clock training cap
or silent label truncation is used. Synthetic runs always remain experimental.
"""

import argparse
import fcntl
import importlib.metadata
import json
import math
import os
import platform
import sys
import uuid
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from ml.evaluation.conversation.intent import InvalidIntent, parse  # noqa: E402
from ml.training.assistant.contract import (  # noqa: E402
    advance,
    messages,
    references,
    sha,
    validate_dataset,
    write,
)
from ml.training.assistant.restore import verify  # noqa: E402
from ml.training.storage import checkpoint_peak, require_storage  # noqa: E402

BASE = ROOT / ".local/models/assistant/qwen3-0.6b"


def lineage(dataset):
    sources = [
        Path(__file__),
        Path(__file__).with_name("contract.py"),
        Path(__file__).with_name("prepare.py"),
        ROOT / "ml/evaluation/conversation/intent.py",
        ROOT / "ml/training/storage.py",
    ]
    return {
        "dataset_sha256": sha(dataset),
        "registry_sha256": sha(ROOT / "ml/registry/assistant-base.json"),
        "environment_sha256": sha(Path(__file__).with_name("uv.lock")),
        "packages": {
            name: importlib.metadata.version(name)
            for name in ["mlx", "mlx-lm", "numpy", "transformers"]
        },
        "sources_sha256": {str(p.relative_to(ROOT)): sha(p) for p in sources},
        "python": sys.version,
        "platform": platform.platform(),
    }


def current_identity(run):
    settings = json.loads((run / "settings.json").read_text())
    actual = {
        "settings_sha256": sha(run / "settings.json"),
        "lineage": lineage(Path(settings["dataset"])),
    }
    if actual != json.loads((run / "identity.json").read_text()):
        raise ValueError(
            "Run configuration, source, dataset or environment changed; preserve this run"
        )
    verify(BASE)
    return settings, validate_dataset(Path(settings["dataset"]))


def verify_checkpoint(run, path):
    """Require the complete checkpoint receipt even for an earlier selected epoch."""
    receipt = json.loads((path / "checkpoint.json").read_text())
    required = {
        "adapters.safetensors",
        "optimizer.safetensors",
        "random.safetensors",
        "adapter_config.json",
        "metrics.json",
    }
    epoch, state, files = receipt.get("epoch"), receipt.get("state"), receipt.get("files")
    if (
        type(epoch) is not int
        or epoch < 1
        or path.name != f"epoch-{epoch:04d}"
        or not isinstance(state, dict)
        or type(state.get("epoch")) is not int
        or state["epoch"] != epoch
        or receipt.get("run_identity") != sha(run / "identity.json")
        or receipt.get("baseline_sha256") != sha(run / "baseline.json")
        or not isinstance(files, dict)
        or set(files) != required
        or any(sha(path / name) != expected for name, expected in files.items())
    ):
        raise ValueError("Checkpoint weights, optimizer or provenance checksum mismatch")
    return receipt


def latest_checkpoint(run):
    directories = list((run / "checkpoints").glob("epoch-*"))
    if not directories:
        return None, None
    if any(not path.name.removeprefix("epoch-").isdigit() for path in directories):
        raise ValueError("Invalid completed checkpoint directory")
    path = max(directories, key=lambda item: int(item.name.removeprefix("epoch-")))
    receipt = verify_checkpoint(run, path)
    return path, receipt


def checkpoint(run, epoch, model, optimizer, state, metrics, settings):
    import mlx.core as mx
    from mlx.utils import tree_flatten

    require_storage(
        ROOT,
        run,
        3,
        checkpoint_peak(
            model.trainable_parameters(), optimizer.state, random=list(mx.random.state)
        ),
    )
    parent = run / "checkpoints"
    parent.mkdir(exist_ok=True)
    temporary = parent / (".incomplete-" + uuid.uuid4().hex)
    temporary.mkdir()
    mx.eval(model.trainable_parameters(), optimizer.state, mx.random.state)
    mx.save_safetensors(
        str(temporary / "adapters.safetensors"), dict(tree_flatten(model.trainable_parameters()))
    )
    mx.save_safetensors(
        str(temporary / "optimizer.safetensors"), dict(tree_flatten(optimizer.state))
    )
    mx.save_safetensors(
        str(temporary / "random.safetensors"),
        {str(i): value for i, value in enumerate(mx.random.state)},
    )
    write(
        temporary / "adapter_config.json",
        {name: settings[name] for name in ["fine_tune_type", "num_layers", "lora_parameters"]},
    )
    write(temporary / "metrics.json", metrics)
    files = {p.name: sha(p) for p in temporary.iterdir()}
    for path in temporary.iterdir():
        with path.open("rb") as stream:
            os.fsync(stream.fileno())
    write(
        temporary / "checkpoint.json",
        {
            "epoch": epoch,
            "state": state,
            "files": files,
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


def restore_random(values):
    import mlx.core as mx

    # MLX 0.32 exposes a read-only, thread-local state sentinel. Reconstruct its
    # two-word Threefry key through the public 64-bit seed API, and prove the
    # round trip instead of replacing the Python module's state attribute.
    if set(values) != {"0"} or values["0"].dtype != mx.uint32 or values["0"].shape != (2,):
        raise ValueError("Unsupported MLX random checkpoint")
    words = values["0"].tolist()
    seed = (words[0] << 32) | words[1]
    if not mx.array_equal(mx.random.key(seed), values["0"]).item():
        raise ValueError("MLX random key cannot be restored through the pinned seed API")
    mx.random.seed(seed)


def tokenized(rows, tokenizer, maximum):
    from mlx_lm.tuner.datasets import ChatDataset

    class NoThinking:
        def apply_chat_template(self, *args, **kwargs):
            return tokenizer.apply_chat_template(*args, **(kwargs | {"enable_thinking": False}))

    dataset = ChatDataset([], NoThinking(), mask_prompt=True)
    result = []
    for row in rows:
        tokens, offset = dataset.process({"messages": messages(row)})
        if not 0 < offset < len(tokens) <= maximum:
            raise ValueError(f"Invalid masking or overlong label in {row['id']}; nothing truncated")
        result.append((tokens, offset))
    return result


def batch(items):
    import mlx.core as mx
    import numpy as np

    length = max(len(tokens) for tokens, _ in items)
    values = np.zeros((len(items), length), dtype=np.int32)
    bounds = []
    for index, (tokens, offset) in enumerate(items):
        values[index, : len(tokens)] = tokens
        bounds.append((offset, len(tokens) - 1))
    return mx.array(values), mx.array(bounds)


def evaluate(model, tokenizer, rows, tokens, settings):
    from mlx_lm import generate
    from mlx_lm.sample_utils import make_sampler
    from mlx_lm.tuner.trainer import default_loss

    model.eval()
    cases, families = [], defaultdict(list)
    weighted_loss, total_tokens = 0.0, 0
    for row, encoded in zip(rows, tokens, strict=True):
        loss, count = default_loss(model, *batch([encoded]))
        loss, count = float(loss.item()), int(count.item())
        if not math.isfinite(loss):
            raise ValueError("Non-finite validation loss")
        weighted_loss += loss * count
        total_tokens += count
        prompt = tokenizer.apply_chat_template(
            messages(row, include_answer=False),
            tokenize=False,
            add_generation_prompt=True,
            enable_thinking=False,
        )
        answer = generate(
            model,
            tokenizer,
            prompt=prompt,
            sampler=make_sampler(temp=0),
            max_tokens=settings["max_output_tokens"],
            verbose=False,
        )
        case = {
            "id": row["id"],
            "family": row["family"],
            "expected": row["expected"],
            "output": answer,
            "schema_valid": False,
            "exact_match": False,
            "unsafe_mutation": False,
        }
        try:
            value = parse(answer, references=references(row))
            case.update(schema_valid=True, actual=value, exact_match=value == row["expected"])
            case["unsafe_mutation"] = (
                value["action"] in {"create", "update", "remove"} and not case["exact_match"]
            )
        except InvalidIntent as error:
            case["rejection"] = str(error)
        cases.append(case)
        families[row["family"]].append(case["exact_match"])
    return {
        "cases": len(cases),
        "families": len(families),
        "exact": sum(c["exact_match"] for c in cases),
        "schema_valid": sum(c["schema_valid"] for c in cases),
        "unsafe_mutations": sum(c["unsafe_mutation"] for c in cases),
        "critical_errors": sum(not c["exact_match"] for c in cases),
        "family_mean_error": sum(1 - sum(group) / len(group) for group in families.values())
        / len(families),
        "loss": weighted_loss / total_tokens,
        "details": cases,
    }


def execute(run, pause_after_epoch=None):
    require_storage(ROOT, run, 3)
    import mlx.core as mx
    import mlx.nn as nn
    import mlx.optimizers as optim
    import numpy as np
    from mlx.utils import tree_flatten, tree_unflatten
    from mlx_lm.tuner.trainer import default_loss
    from mlx_lm.tuner.utils import linear_to_lora_layers
    from mlx_lm.utils import load

    settings, dataset = current_identity(run)
    mx.random.seed(settings["seed"])
    model, tokenizer = load(str(BASE), tokenizer_config={"trust_remote_code": False})
    partitions = {
        part: [r for r in dataset["samples"] if r["partition"] == part]
        for part in ["train", "validation"]
    }
    tokens = {
        part: tokenized(rows, tokenizer, settings["max_seq_length"])
        for part, rows in partitions.items()
    }
    write(
        run / "tokenization.json",
        {
            "maximum_tokens": max(len(t[0]) for part in tokens.values() for t in part),
            "truncated": 0,
            "thinking": False,
        },
    )
    path, receipt = latest_checkpoint(run)
    model.freeze()
    linear_to_lora_layers(model, settings["num_layers"], settings["lora_parameters"])
    optimizer = optim.Adam(learning_rate=settings["learning_rate"])
    optimizer.init(model.trainable_parameters())
    state = {
        "epoch": 0,
        "steps": 0,
        "stale_epochs": 0,
        "best_epoch": None,
        "best_score": None,
        "stopped": False,
    }
    if receipt:
        weights = mx.load(str(path / "adapters.safetensors"))
        expected = dict(tree_flatten(model.trainable_parameters()))
        if set(weights) != set(expected) or any(
            weights[k].shape != expected[k].shape for k in expected
        ):
            raise ValueError("Checkpoint adapter architecture changed")
        model.load_weights(list(weights.items()), strict=False)
        optimizer.state = tree_unflatten(list(mx.load(str(path / "optimizer.safetensors")).items()))
        rng = mx.load(str(path / "random.safetensors"))
        restore_random(rng)
        state = receipt["state"]
    elif not (run / "baseline.json").exists():
        baseline = evaluate(
            model, tokenizer, partitions["validation"], tokens["validation"], settings
        )
        write(run / "baseline.json", baseline)
        print(
            "BASELINE " + json.dumps({k: v for k, v in baseline.items() if k != "details"}),
            flush=True,
        )
    loss_grad = nn.value_and_grad(model, default_loss)
    for epoch in range(state["epoch"] + 1, settings["max_epochs"] + 1):
        if state["stopped"]:
            break
        require_storage(
            ROOT,
            run,
            3,
            checkpoint_peak(
                model.trainable_parameters(), optimizer.state, random=list(mx.random.state)
            ),
        )
        model.train()
        # The epoch permutation does not depend on validation generation or an
        # interrupted epoch. Dropout is fixed at zero in the saved configuration.
        indices = np.random.default_rng(settings["seed"] + epoch).permutation(len(tokens["train"]))
        for offset in range(0, len(indices), settings["batch_size"]):
            items = [tokens["train"][i] for i in indices[offset : offset + settings["batch_size"]]]
            (loss, _), gradient = loss_grad(model, *batch(items))
            optimizer.update(model, gradient)
            mx.eval(model.trainable_parameters(), optimizer.state, loss)
            if not math.isfinite(float(loss.item())):
                raise ValueError(
                    "Non-finite training loss; last complete checkpoint remains intact"
                )
            state["steps"] += 1
            print(f"STEP {state['steps']} epoch={epoch} loss={loss.item():.6f}", flush=True)
        metrics = evaluate(
            model, tokenizer, partitions["validation"], tokens["validation"], settings
        )
        state = advance(state, metrics, epoch, settings["patience"])
        checkpoint(run, epoch, model, optimizer, state, metrics, settings)
        write(run / "progress.json", state)
        print("EPOCH " + json.dumps(state), flush=True)
        if pause_after_epoch is not None and epoch >= pause_after_epoch:
            print("Paused after an atomic epoch checkpoint", flush=True)
            return
    write(
        run / "result.json",
        {
            "schema_version": 1,
            "status": "trained-experimental-only",
            "qualified": False,
            "selection": state,
            "identity_sha256": sha(run / "identity.json"),
            "dataset_kind": dataset["kind"],
            "independent_real_dialogues": dataset.get("independent_real_dialogues", 0),
            "deployment_parity": "not_evaluated",
            "human_review": dataset.get("human_review", "recorded_per_sample"),
        },
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["start", "resume"])
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--dataset", type=Path)
    parser.add_argument("--max-epochs", type=int, default=20)
    parser.add_argument("--patience", type=int, default=3)
    parser.add_argument("--batch-size", type=int, default=2)
    parser.add_argument("--num-layers", type=int, default=8)
    parser.add_argument("--learning-rate", type=float, default=0.0001)
    parser.add_argument("--seed", type=int, default=20260917)
    parser.add_argument("--pause-after-epoch", type=int)
    args = parser.parse_args()
    run = args.run.resolve()
    if not run.is_relative_to(ROOT / ".local/runs"):
        raise ValueError("Training artifacts belong below .local/runs")
    os.environ.update(HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1")
    if args.action == "start":
        if (
            not args.dataset
            or min(args.max_epochs, args.patience, args.batch_size, args.num_layers) < 1
        ):
            raise ValueError("Dataset and positive training settings are required")
        if args.num_layers > 28 or not 0 < args.learning_rate <= 0.001:
            raise ValueError("Unsupported Qwen3 adaptation settings")
        dataset = args.dataset.resolve(strict=True)
        validate_dataset(dataset)
        verify(BASE)
        run.mkdir(parents=True, exist_ok=False)
        settings = {
            "dataset": str(dataset),
            "seed": args.seed,
            "fine_tune_type": "lora",
            "num_layers": args.num_layers,
            "batch_size": args.batch_size,
            "learning_rate": args.learning_rate,
            "max_epochs": args.max_epochs,
            "patience": args.patience,
            "max_seq_length": 1536,
            "max_output_tokens": 192,
            "lora_parameters": {"rank": 8, "scale": 20.0, "dropout": 0.0},
        }
        write(run / "settings.json", settings)
        write(
            run / "identity.json",
            {"settings_sha256": sha(run / "settings.json"), "lineage": lineage(dataset)},
        )
    with (run / "training.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        execute(run, args.pause_after_epoch)


if __name__ == "__main__":
    main()
