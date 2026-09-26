"""Verify Qwen LoRA, fusion and local GGUF execution using invented examples.

This deliberately short run is a compatibility check. It is not a resumable
production trainer, benchmark, human-reviewed dataset or qualified app model.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import types
from pathlib import Path

from restore import ROOT, sha, verify

sys.path.insert(0, str(ROOT))
from ml.data.synthesis.assistant_smoke import examples, messages  # noqa: E402

BASE = ROOT / ".local/models/assistant/qwen3-0.6b"
CONVERTER = ROOT / ".local/upstream/llama.cpp"
EXPORT_PYTHON = ROOT / ".local/envs/assistant-export/bin/python"
RUNTIME = ROOT / ".local/builds/assistant-runtime-41fc758/bin/llama-completion"
SEED = 20260916


def dump(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(path)


class TokenizerWithoutThinking:
    # MLX-LM's ChatDataset does not forward per-example template kwargs.
    # Use the same explicit Qwen template setting during training and inference.
    def __init__(self, tokenizer):
        self.tokenizer = tokenizer

    def apply_chat_template(self, *args, **kwargs):
        return self.tokenizer.apply_chat_template(*args, **(kwargs | {"enable_thinking": False}))


def train(output):
    import numpy as np
    from mlx_lm.lora import CONFIG_DEFAULTS, train_model
    from mlx_lm.tuner.datasets import ChatDataset
    from mlx_lm.utils import load

    config = json.loads((output / "config.json").read_text())
    np.random.seed(config["seed"])
    model, tokenizer = load(str(BASE), tokenizer_config={"trust_remote_code": False})
    tokenizer = TokenizerWithoutThinking(tokenizer)
    partitions = {}
    maximum = 0
    for partition in ["train", "valid"]:
        data = [
            json.loads(line) for line in (output / f"{partition}.jsonl").read_text().splitlines()
        ]
        dataset = ChatDataset(data, tokenizer, mask_prompt=True)
        for row in data:
            tokens, offset = dataset.process(row)
            maximum = max(maximum, len(tokens))
            if not 0 < offset < len(tokens) <= config["max_seq_length"]:
                raise ValueError("Invalid masking or overlong example; no sequence was truncated")
        partitions[partition] = dataset
    dump(
        output / "tokenization.json", {"maximum_tokens": maximum, "truncated": 0, "thinking": False}
    )
    train_model(
        types.SimpleNamespace(**(CONFIG_DEFAULTS | config)),
        model,
        partitions["train"],
        partitions["valid"],
    )


def fusion_check(output):
    import mlx.core as mx
    from mlx_lm.utils import load

    adapted, tokenizer = load(str(BASE), adapter_path=str(output / "adapters"))
    fused, _ = load(str(output / "fused"))
    checks = []
    for row in examples():
        tokens = tokenizer.apply_chat_template(
            messages(row, include_answer=False), add_generation_prompt=True, enable_thinking=False
        )
        inputs = mx.array([tokens])
        a = adapted(inputs)[:, -1, :].astype(mx.float32)
        b = fused(inputs)[:, -1, :].astype(mx.float32)
        same = bool((mx.argmax(a, axis=-1) == mx.argmax(b, axis=-1)).item())
        checks.append(
            {
                "id": row["id"],
                "same_next_token": same,
                "max_absolute_logit_difference": float(mx.max(mx.abs(a - b)).item()),
            }
        )
    dump(output / "fusion-parity.json", {"kind": "greedy-next-token-only", "cases": checks})
    if not all(row["same_next_token"] for row in checks):
        raise ValueError("Fusion changed a checked greedy next token; inspect parity report")


def preserve_tokenizer(output):
    """LoRA changes weights only. Preserve the compatible, pinned tokenizer.

    Transformers 5 reserializes extra_special_tokens in a format the pinned
    Transformers 4 GGUF exporter cannot read. Never rewrite token IDs to adapt it.
    """
    from transformers import AutoTokenizer

    verify(BASE)
    destination = output / "fused"
    original = AutoTokenizer.from_pretrained(BASE, local_files_only=True)
    fused = AutoTokenizer.from_pretrained(destination, local_files_only=True)
    checks = {
        "vocabulary": original.get_vocab() == fused.get_vocab(),
        "added_vocabulary": original.get_added_vocab() == fused.get_added_vocab(),
        "special_ids": original.all_special_ids == fused.all_special_ids,
        "chat_template": original.chat_template == fused.chat_template,
    }
    for name in ["bos_token_id", "eos_token_id", "pad_token_id"]:
        checks[name] = getattr(original, name) == getattr(fused, name)
    if not all(checks.values()):
        raise ValueError(f"Fusion changed tokenizer semantics; cannot restore original: {checks}")
    hashes = {}
    for name in ["tokenizer.json", "tokenizer_config.json", "vocab.json", "merges.txt"]:
        shutil.copyfile(BASE / name, destination / name)
        hashes[name] = sha(destination / name)
    # Both template representations were checked above; keep the pinned one.
    (destination / "chat_template.jinja").unlink(missing_ok=True)
    dump(output / "tokenizer-preservation.json", {"checks": checks, "restored_sha256": hashes})


def prepare(output):
    from mlx_lm.utils import load_tokenizer

    registry = verify(BASE)
    revision = subprocess.check_output(
        ["git", "-C", str(CONVERTER), "rev-parse", "HEAD"], text=True
    ).strip()
    if revision != registry["converter_revision"]:
        raise ValueError("Converter revision differs from the registry")
    if subprocess.check_output(
        ["git", "-C", str(CONVERTER), "status", "--porcelain"], text=True
    ).strip():
        raise ValueError("Converter source has local changes")
    if not RUNTIME.is_file() or not EXPORT_PYTHON.is_file():
        raise ValueError("Restore the separate export environment and build llama-completion first")
    output.mkdir(parents=True, exist_ok=False)
    rows = examples()
    families = [{r["family"] for r in rows if r["partition"] == p} for p in ["train", "valid"]]
    if families[0] & families[1]:
        raise ValueError("Scenario families overlap across partitions")
    for partition in ["train", "valid"]:
        (output / f"{partition}.jsonl").write_text(
            "".join(
                json.dumps({"messages": messages(row)}, ensure_ascii=False) + "\n"
                for row in rows
                if row["partition"] == partition
            )
        )
    dump(output / "samples.json", rows)
    config = {
        "model": str(BASE),
        "train": True,
        "data": str(output),
        "seed": SEED,
        "fine_tune_type": "lora",
        "num_layers": 4,
        "batch_size": 1,
        "iters": 8,
        "val_batches": 4,
        "learning_rate": 0.00001,
        "steps_per_report": 1,
        "steps_per_eval": 4,
        "save_every": 4,
        "max_seq_length": 1024,
        "mask_prompt": True,
        "adapter_path": str(output / "adapters"),
        "lora_parameters": {"rank": 8, "dropout": 0.0, "scale": 20.0},
    }
    dump(output / "config.json", config)
    tokenizer = load_tokenizer(BASE, {"trust_remote_code": False})
    prompt = tokenizer.apply_chat_template(
        messages(rows[0], include_answer=False),
        tokenize=False,
        add_generation_prompt=True,
        enable_thinking=False,
    )
    (output / "runtime-prompt.txt").write_text(prompt)
    return {
        "schema_version": 1,
        "kind": "synthetic-training-export-smoke",
        "qualified": False,
        "status": "prepared",
        "seed": SEED,
        "base_revision": registry["revision"],
        "base_sha256": registry["files"]["model.safetensors"]["sha256"],
        "converter_revision": revision,
        "runtime_sha256": sha(RUNTIME),
        "environment_sha256": sha(Path(__file__).with_name("uv.lock")),
        "export_environment_sha256": sha(Path(__file__).parent / "export/uv.lock"),
        "source_sha256": sha(Path(__file__)),
        "source_files_sha256": {
            str(path.relative_to(ROOT)): sha(path)
            for path in [
                Path(__file__),
                Path(__file__).with_name("restore.py"),
                ROOT / "ml/data/synthesis/assistant_smoke.py",
                ROOT / "ml/registry/assistant-base.json",
            ]
        },
        "dataset_sha256": sha(output / "samples.json"),
        "configuration_sha256": sha(output / "config.json"),
        "stages": [],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--execute", action="store_true")
    stages = {"train": train, "fusion-check": fusion_check, "tokenizer": preserve_tokenizer}
    parser.add_argument("--stage", choices=stages, help=argparse.SUPPRESS)
    args = parser.parse_args()
    output = args.output.resolve()
    if args.stage:
        stages[args.stage](output)
        return
    report = prepare(output)
    dump(output / "run.json", report)
    if not args.execute:
        print(f"Prepared synthetic run: {output}")
        return

    def convert(source, name):
        return [
            str(EXPORT_PYTHON),
            str(CONVERTER / "convert_hf_to_gguf.py"),
            str(source),
            "--outfile",
            str(output / f"{name}.gguf"),
            "--outtype",
            "f16",
        ]

    def execute(name):
        return [
            str(RUNTIME),
            "-m",
            str(output / f"{name}.gguf"),
            "-f",
            str(output / "runtime-prompt.txt"),
            "-no-cnv",
            "--no-display-prompt",
            "--simple-io",
            "--color",
            "off",
            "--temp",
            "0",
            "--seed",
            str(SEED),
            "-n",
            "128",
            "-c",
            "2048",
            "-t",
            "4",
        ]

    commands = [
        ("baseline-export", convert(BASE, "baseline")),
        ("baseline-runtime", execute("baseline")),
        (
            "training",
            [sys.executable, str(Path(__file__)), "--output", str(output), "--stage", "train"],
        ),
        (
            "fusion",
            [
                sys.executable,
                "-m",
                "mlx_lm",
                "fuse",
                "--model",
                str(BASE),
                "--adapter-path",
                str(output / "adapters"),
                "--save-path",
                str(output / "fused"),
            ],
        ),
        (
            "tokenizer-preservation",
            [sys.executable, str(Path(__file__)), "--output", str(output), "--stage", "tokenizer"],
        ),
        (
            "fusion-parity",
            [
                sys.executable,
                str(Path(__file__)),
                "--output",
                str(output),
                "--stage",
                "fusion-check",
            ],
        ),
        ("fused-export", convert(output / "fused", "assistant")),
        ("fused-runtime", execute("assistant")),
    ]
    env = dict(
        os.environ, HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1", TOKENIZERS_PARALLELISM="false"
    )
    try:
        for name, command in commands:
            stage = {"name": name, "command": command, "status": "running", "started": time.time()}
            report["stages"].append(stage)
            report["status"] = "running"
            dump(output / "run.json", report)
            with (
                (output / f"{name}.stdout").open("w") as stdout,
                (output / f"{name}.stderr").open("w") as stderr,
            ):
                subprocess.run(command, cwd=ROOT, env=env, stdout=stdout, stderr=stderr, check=True)
            if name.endswith("runtime") and not (output / f"{name}.stdout").read_text().strip():
                raise ValueError(f"{name} produced no output")
            stage.update(status="completed", elapsed_seconds=time.time() - stage["started"])
            dump(output / "run.json", report)
        report.update(
            status="exported-desktop-smoke-only",
            artifact_sha256=sha(output / "assistant.gguf"),
            baseline_artifact_sha256=sha(output / "baseline.gguf"),
            adapter_sha256=sha(output / "adapters/adapters.safetensors"),
        )
    except BaseException as error:
        stage.update(status="failed", error=f"{type(error).__name__}: {error}")
        report["status"] = "interrupted-or-failed"
        dump(output / "run.json", report)
        raise
    dump(output / "run.json", report)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
