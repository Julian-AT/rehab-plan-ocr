"""Compare baseline and LoRA GGUF outputs on the small, invented smoke corpus.

This is an offline desktop compatibility/quality diagnostic, not an independent
holdout, a latency benchmark or a release qualification. No operation is executed.
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from ml.data.synthesis.assistant_smoke import messages  # noqa: E402
from ml.evaluation.conversation.intent import InvalidIntent, parse, validate  # noqa: E402
from ml.evaluation.conversation.runtime_prompt import arguments as prompt_arguments  # noqa: E402
from ml.training.assistant.restore import verify  # noqa: E402


def sha(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def compare(run, destination, runtime, base):
    from transformers import AutoTokenizer

    identity = json.loads((run / "run.json").read_text())
    verify(base)
    if identity["status"] != "exported-desktop-smoke-only":
        raise ValueError("The training/export smoke run did not finish")
    if sha(runtime) != identity["runtime_sha256"]:
        raise ValueError("Runtime differs from the training/export run")
    if sha(run / "assistant.gguf") != identity["artifact_sha256"]:
        raise ValueError("Fused GGUF differs from the recorded export")
    if (
        "baseline_artifact_sha256" in identity
        and sha(run / "baseline.gguf") != identity["baseline_artifact_sha256"]
    ):
        raise ValueError("Baseline GGUF differs from the recorded export")
    rows = json.loads((run / "samples.json").read_text())
    if sha(run / "samples.json") != identity["dataset_sha256"]:
        raise ValueError("Samples differ from the recorded smoke corpus")
    tokenizer = AutoTokenizer.from_pretrained(base, local_files_only=True)
    destination.mkdir(parents=True, exist_ok=False)
    result = {
        "schema_version": 1,
        "kind": "invented-smoke-diagnostic",
        "qualified": False,
        "human_review": "pending",
        "independent_real_dialogues": 0,
        "training_seen_cases": sum(r["partition"] == "train" for r in rows),
        "validation_selection_only_cases": sum(r["partition"] == "valid" for r in rows),
        "run_identity": sha(run / "run.json"),
        "evaluator_sha256": sha(Path(__file__)),
        "validator_sha256": sha(Path(__file__).with_name("intent.py")),
        "artifacts": {name: sha(run / f"{name}.gguf") for name in ["baseline", "assistant"]},
        "cases": [],
    }
    env = dict(os.environ, HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1")
    for index, row in enumerate(rows):
        references = [row["context"]["selected"]] if "selected" in row["context"] else []
        validate(row["expected"], references=references)
        prompt = destination / f"{row['id']}.prompt.txt"
        prompt.write_text(
            tokenizer.apply_chat_template(
                messages(row, include_answer=False),
                tokenize=False,
                add_generation_prompt=True,
                enable_thinking=False,
            )
        )
        # Alternate order for paired cases. These process times are not a benchmark.
        order = ["baseline", "assistant"] if index % 2 == 0 else ["assistant", "baseline"]
        for model in order:
            command = [
                str(runtime),
                "-m",
                str(run / f"{model}.gguf"),
                *prompt_arguments(prompt),
                "-no-cnv",
                "--no-display-prompt",
                "--simple-io",
                "--color",
                "off",
                "--temp",
                "0",
                "--seed",
                "20260916",
                "-n",
                "128",
                "-c",
                "2048",
                "-t",
                "4",
            ]
            with (destination / f"{row['id']}.{model}.stderr").open("w") as stderr:
                completed = subprocess.run(
                    command,
                    env=env,
                    cwd=ROOT,
                    check=True,
                    stdout=subprocess.PIPE,
                    stderr=stderr,
                    text=True,
                    timeout=120,
                )
            (destination / f"{row['id']}.{model}.stdout").write_text(completed.stdout)
            case = {
                "id": row["id"],
                "family": row["family"],
                "partition": row["partition"],
                "model": model,
                "expected": row["expected"],
                "schema_valid": False,
                "exact_match": False,
                "unsafe_mutation": False,
            }
            try:
                parsed = parse(completed.stdout, references=references)
                case.update(schema_valid=True, actual=parsed, exact_match=parsed == row["expected"])
                case["unsafe_mutation"] = (
                    parsed["action"] in {"create", "update", "remove"} and not case["exact_match"]
                )
            except InvalidIntent as error:
                case["rejection"] = str(error)
            result["cases"].append(case)
            print(
                f"{row['id']} {model}: schema={case['schema_valid']} exact={case['exact_match']}",
                flush=True,
            )
            (destination / "report.json").write_text(
                json.dumps(result, ensure_ascii=False, indent=2) + "\n"
            )
    result["counts"] = {}
    for model in ["baseline", "assistant"]:
        result["counts"][model] = {}
        for partition in ["train", "valid"]:
            subset = [
                c for c in result["cases"] if c["model"] == model and c["partition"] == partition
            ]
            result["counts"][model][partition] = {
                "cases": len(subset),
                **{
                    key: sum(c[key] for c in subset)
                    for key in ["schema_valid", "exact_match", "unsafe_mutation"]
                },
            }
    result["status"] = "completed-experimental-only"
    (destination / "report.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    )
    print(json.dumps(result["counts"], indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--runtime",
        type=Path,
        default=ROOT / ".local/builds/assistant-runtime-41fc758/bin/llama-completion",
    )
    parser.add_argument("--base", type=Path, default=ROOT / ".local/models/assistant/qwen3-0.6b")
    args = parser.parse_args()
    compare(args.run.resolve(), args.output.resolve(), args.runtime.resolve(), args.base.resolve())


if __name__ == "__main__":
    main()
