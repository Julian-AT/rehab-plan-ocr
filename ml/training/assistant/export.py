"""Fuse the validation-selected adapter and audit complete local-runtime answers."""

import argparse
import gc
import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from ml.evaluation.conversation.intent import InvalidIntent, parse  # noqa: E402
from ml.evaluation.conversation.runtime_prompt import arguments as prompt_arguments  # noqa: E402
from ml.training.assistant.contract import messages, references, sha, write  # noqa: E402
from ml.training.assistant.train import BASE, current_identity, latest_checkpoint  # noqa: E402

CONVERTER = ROOT / ".local/upstream/llama.cpp"
RUNTIME = ROOT / ".local/builds/assistant-runtime-41fc758/bin/llama-completion"
EXPORT_PYTHON = ROOT / ".local/envs/assistant-export/bin/python"


def selected_checkpoint(run):
    settings, data = current_identity(run)
    _, latest = latest_checkpoint(run)
    result = json.loads((run / "result.json").read_text())
    if (
        not latest
        or result["selection"] != latest["state"]
        or result["identity_sha256"] != sha(run / "identity.json")
    ):
        raise ValueError("Training did not finish with the recorded checkpoint selection")
    checkpoint = run / "checkpoints" / f"epoch-{latest['state']['best_epoch']:04d}"
    receipt = json.loads((checkpoint / "checkpoint.json").read_text())
    if receipt["run_identity"] != sha(run / "identity.json") or any(
        sha(checkpoint / name) != value for name, value in receipt["files"].items()
    ):
        raise ValueError("Selected adapter or evidence changed")
    return settings, data, checkpoint


def clean_answer(text):
    return text.strip().removesuffix("[end of text]").rstrip()


def parity(run, destination):
    import mlx.core as mx
    from mlx_lm import generate
    from mlx_lm.sample_utils import make_sampler
    from mlx_lm.utils import load

    settings, data, checkpoint = selected_checkpoint(run)
    rows = [row for row in data["samples"] if row["partition"] == "validation"]
    answers = {}
    for name, source, adapter in [
        ("adapter", BASE, checkpoint),
        ("fused", destination / "fused", None),
    ]:
        model, tokenizer = load(
            str(source),
            adapter_path=str(adapter) if adapter else None,
            tokenizer_config={"trust_remote_code": False},
        )
        model.eval()
        answers[name] = []
        for row in rows:
            prompt = tokenizer.apply_chat_template(
                messages(row, include_answer=False),
                tokenize=False,
                add_generation_prompt=True,
                enable_thinking=False,
            )
            answers[name].append(
                generate(
                    model,
                    tokenizer,
                    prompt=prompt,
                    sampler=make_sampler(temp=0),
                    max_tokens=settings["max_output_tokens"],
                    verbose=False,
                )
            )
        del model
        gc.collect()
        mx.clear_cache()
    report = {
        "schema_version": 1,
        "kind": "complete-greedy-development-answers",
        "qualified": False,
        "cases": [],
        "run_identity_sha256": sha(run / "identity.json"),
    }
    for index, row in enumerate(rows):
        prompt = destination / f"case-{index:04}.prompt.txt"
        prompt.write_text(
            tokenizer.apply_chat_template(
                messages(row, include_answer=False),
                tokenize=False,
                add_generation_prompt=True,
                enable_thinking=False,
            )
        )
        output = {name: values[index] for name, values in answers.items()}
        for name in ["baseline", "assistant"] if index % 2 == 0 else ["assistant", "baseline"]:
            command = [
                str(RUNTIME),
                "-m",
                str(destination / f"{name}.gguf"),
                *prompt_arguments(prompt),
                "-no-cnv",
                "--no-display-prompt",
                "--simple-io",
                "--color",
                "off",
                "--temp",
                "0",
                "--seed",
                str(settings["seed"]),
                "-n",
                str(settings["max_output_tokens"]),
                "-c",
                "2048",
                "-t",
                "4",
            ]
            with (destination / f"case-{index:04}.{name}.stderr").open("w") as stderr:
                result = subprocess.run(
                    command,
                    cwd=ROOT,
                    stdout=subprocess.PIPE,
                    stderr=stderr,
                    text=True,
                    check=True,
                    timeout=120,
                )
            output[name] = result.stdout
        case = {
            "id": row["id"],
            "family": row["family"],
            "expected": row["expected"],
            "outputs": output,
            "providers": {},
        }
        for name, answer in output.items():
            outcome = {"schema_valid": False, "exact_match": False, "unsafe_mutation": False}
            try:
                parsed = parse(answer, references=references(row))
                outcome.update(
                    schema_valid=True, exact_match=parsed == row["expected"], actual=parsed
                )
                outcome["unsafe_mutation"] = (
                    parsed["action"] in {"create", "update", "remove"}
                    and not outcome["exact_match"]
                )
            except InvalidIntent as error:
                outcome["rejection"] = str(error)
            case["providers"][name] = outcome
        case["fusion_equal"] = clean_answer(output["adapter"]) == clean_answer(output["fused"])
        case["runtime_equal"] = clean_answer(output["fused"]) == clean_answer(output["assistant"])
        report["cases"].append(case)
        write(destination / "parity.json", report)
        print(
            f"{row['id']}: fusion={case['fusion_equal']} runtime={case['runtime_equal']}",
            flush=True,
        )
    report["counts"] = {
        name: {
            metric: sum(c["providers"][name][metric] for c in report["cases"])
            for metric in ["schema_valid", "exact_match", "unsafe_mutation"]
        }
        for name in ["adapter", "fused", "baseline", "assistant"]
    }
    report["complete_text_parity"] = all(
        c["fusion_equal"] and c["runtime_equal"] for c in report["cases"]
    )
    write(destination / "parity.json", report)
    if not report["complete_text_parity"]:
        raise ValueError(
            "Complete-answer deployment parity failed; retain experiment without promotion"
        )


def export(run, destination):
    _, _, checkpoint = selected_checkpoint(run)
    registry = json.loads((ROOT / "ml/registry/assistant-base.json").read_text())
    revision = subprocess.check_output(
        ["git", "-C", str(CONVERTER), "rev-parse", "HEAD"], text=True
    ).strip()
    dirty = subprocess.check_output(
        ["git", "-C", str(CONVERTER), "status", "--porcelain"], text=True
    ).strip()
    runtime = json.loads((RUNTIME.parent.parent / "receipt.json").read_text())
    if (
        revision != registry["converter_revision"]
        or dirty
        or runtime["source_revision"] != revision
        or runtime["runtime_sha256"] != sha(RUNTIME)
    ):
        raise ValueError("Converter or local runtime differs from its pinned identity")
    destination.mkdir(parents=True, exist_ok=False)
    report = {
        "schema_version": 1,
        "qualified": False,
        "status": "running",
        "stages": [],
        "run_identity_sha256": sha(run / "identity.json"),
        "checkpoint_sha256": sha(checkpoint / "checkpoint.json"),
        "converter_revision": revision,
        "runtime_sha256": sha(RUNTIME),
        "source_sha256": sha(Path(__file__)),
        "tokenizer_helper_sha256": sha(Path(__file__).with_name("smoke.py")),
        "export_environment_sha256": sha(Path(__file__).parent / "export/uv.lock"),
    }
    commands = [
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
                str(checkpoint),
                "--save-path",
                str(destination / "fused"),
            ],
        ),
        (
            "tokenizer",
            [
                sys.executable,
                str(Path(__file__).with_name("smoke.py")),
                "--output",
                str(destination),
                "--stage",
                "tokenizer",
            ],
        ),
    ]
    for name, model in [("baseline", BASE), ("assistant", destination / "fused")]:
        commands.append(
            (
                name + "-export",
                [
                    str(EXPORT_PYTHON),
                    str(CONVERTER / "convert_hf_to_gguf.py"),
                    str(model),
                    "--outfile",
                    str(destination / f"{name}.gguf"),
                    "--outtype",
                    "f16",
                ],
            )
        )
    commands.append(
        (
            "complete-parity",
            [
                sys.executable,
                str(Path(__file__)),
                "--run",
                str(run),
                "--output",
                str(destination),
                "--parity",
            ],
        )
    )
    try:
        for name, command in commands:
            stage = {"name": name, "command": command, "status": "running", "started": time.time()}
            report["stages"].append(stage)
            write(destination / "export.json", report)
            with (destination / (name + ".log")).open("w") as log:
                subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
            stage.update(status="passed", elapsed_seconds=time.time() - stage["started"])
        report["status"] = "desktop-parity-passed-experimental-only"
    except BaseException as error:
        report["status"] = "interrupted-or-failed"
        report["stages"][-1].update(
            status="failed",
            error_type=type(error).__name__,
            exit_code=getattr(error, "returncode", None),
        )
        raise
    finally:
        report["artifacts"] = {
            name: sha(destination / name)
            for name in ["baseline.gguf", "assistant.gguf", "parity.json"]
            if (destination / name).is_file()
        }
        write(destination / "export.json", report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--parity", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    os.environ.update(HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1", TOKENIZERS_PARALLELISM="false")
    run = args.run.resolve()
    destination = (args.output or run / "deployment").resolve()
    if not destination.is_relative_to(ROOT / ".local"):
        raise ValueError("Model exports belong in ignored .local storage")
    (parity if args.parity else export)(run, destination)


if __name__ == "__main__":
    main()
