"""Recheck failed assistant export cases with explicit desktop CPU/backend settings."""

import argparse
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

VARIANTS = ["desktop-auto", "cpu-desktop-batch", "cpu-native-batch"]


def command(runtime, model, prompt, variant, settings):
    if variant not in VARIANTS:
        raise ValueError("Unknown backend diagnostic variant")
    native_batch = variant == "cpu-native-batch"
    result = [
        str(runtime),
        "-m",
        str(model),
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
        "-tb",
        "4",
        "--batch-size",
        "512" if native_batch else "2048",
        "--ubatch-size",
        "128" if native_batch else "512",
        "--flash-attn",
        "auto",
        "--cache-type-k",
        "f16",
        "--cache-type-v",
        "f16",
        "--n-gpu-layers",
        "auto" if variant == "desktop-auto" else "0",
    ]
    if variant != "desktop-auto":
        result.extend(["--no-kv-offload", "--no-op-offload"])
    return result


def observations(answer, row):
    result = {"schema_valid": False, "exact_match": False, "unsafe_mutation": False}
    try:
        actual = parse(answer, references=references(row))
        result.update(schema_valid=True, exact_match=actual == row["expected"], actual=actual)
        result["unsafe_mutation"] = (
            actual["action"] in {"create", "update", "remove"} and not result["exact_match"]
        )
    except InvalidIntent as error:
        result["rejection"] = str(error)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    run, output = args.run.resolve(strict=True), args.output.resolve()
    if not output.is_relative_to(ROOT / ".local/runs") or output.exists():
        parser.error("Use a new private run directory; preserve all earlier results")
    os.environ.update(HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1", TOKENIZERS_PARALLELISM="false")
    from transformers import AutoTokenizer

    from ml.training.assistant.export import BASE, RUNTIME, clean_answer, selected_checkpoint

    settings, dataset, checkpoint = selected_checkpoint(run)
    deployment = run / "deployment"
    export = json.loads((deployment / "export.json").read_text())
    runtime_receipt = RUNTIME.parent.parent / "receipt.json"
    runtime = json.loads(runtime_receipt.read_text())
    registry = json.loads((ROOT / "ml/registry/assistant-base.json").read_text())
    model = deployment / "assistant.gguf"
    prior_path = deployment / "parity.json"
    if (
        export["runtime_sha256"] != sha(RUNTIME)
        or runtime["runtime_sha256"] != sha(RUNTIME)
        or export["converter_revision"] != registry["converter_revision"]
        or runtime["source_revision"] != registry["converter_revision"]
        or export["checkpoint_sha256"] != sha(checkpoint / "checkpoint.json")
        or export["run_identity_sha256"] != sha(run / "identity.json")
        or export["artifacts"]["assistant.gguf"] != sha(model)
        or export["artifacts"]["parity.json"] != sha(prior_path)
    ):
        raise ValueError("Runtime, model or selected export evidence changed")
    prior = json.loads(prior_path.read_text())
    rows = [row for row in dataset["samples"] if row["partition"] == "validation"]
    if [c["id"] for c in prior["cases"]] != [r["id"] for r in rows]:
        raise ValueError("Earlier parity cases differ from complete validation")
    tokenizer = AutoTokenizer.from_pretrained(
        str(BASE), trust_remote_code=False, local_files_only=True
    )
    selected = []
    for index, (case, row) in enumerate(zip(prior["cases"], rows, strict=True)):
        if case["expected"] != row["expected"] or case["family"] != row["family"]:
            raise ValueError("Earlier parity targets changed")
        if case["runtime_equal"]:
            continue
        prompt = deployment / f"case-{index:04}.prompt.txt"
        expected = tokenizer.apply_chat_template(
            messages(row, include_answer=False),
            tokenize=False,
            add_generation_prompt=True,
            enable_thinking=False,
        )
        if prompt.read_text() != expected:
            raise ValueError("Retained prompt differs from the verified dataset/template")
        selected.append((index, case, row, prompt))
    if not selected:
        raise ValueError("No failed complete-answer parity cases to diagnose")
    sources = [model, prior_path, deployment / "export.json", runtime_receipt, RUNTIME]
    identities = {str(path.relative_to(ROOT)): sha(path) for path in sources}
    output.mkdir()
    report = {
        "schema_version": 1,
        "kind": "assistant-backend-parity-diagnostic",
        "status": "running",
        "diagnostic": True,
        "qualified": False,
        "physical_device": False,
        "shipping_ios_route": False,
        "independent_new_cases": 0,
        "subset": "earlier-runtime-parity-failures",
        "source_sha256": sha(Path(__file__)),
        "sources": identities,
        "native_parameter_source_sha256": sha(
            ROOT / "packages/apple/LocalAssistant/Native/Assistant.cpp"
        ),
        "cases": [],
    }
    write(output / "report.json", report)
    env = {k: v for k, v in os.environ.items() if not k.startswith("LLAMA_ARG_")}
    try:
        for position, (index, case, row, prompt) in enumerate(selected):
            result = {"id": row["id"], "prompt_sha256": sha(prompt), "variants": {}}
            order = VARIANTS[position % len(VARIANTS) :] + VARIANTS[: position % len(VARIANTS)]
            for variant in order:
                arguments = command(RUNTIME, model, prompt, variant, settings)
                started = time.monotonic()
                with (output / f"case-{index:04}.{variant}.stderr").open("w") as stderr:
                    process = subprocess.run(
                        arguments,
                        cwd=ROOT,
                        env=env,
                        text=True,
                        stdout=subprocess.PIPE,
                        stderr=stderr,
                        check=True,
                        timeout=120,
                    )
                (output / f"case-{index:04}.{variant}.txt").write_text(process.stdout)
                result["variants"][variant] = {
                    "command": arguments,
                    "elapsed_seconds": time.monotonic() - started,
                    "answer_sha256": sha(output / f"case-{index:04}.{variant}.txt"),
                    "equals_fused": clean_answer(process.stdout)
                    == clean_answer(case["outputs"]["fused"]),
                    "equals_prior_runtime": clean_answer(process.stdout)
                    == clean_answer(case["outputs"]["assistant"]),
                    **observations(process.stdout, row),
                }
            report["cases"].append(result)
            write(output / "report.json", report)
            print(f"Diagnosed {row['id']}", flush=True)
        if identities != {str(path.relative_to(ROOT)): sha(path) for path in sources}:
            raise ValueError("Source evidence changed during diagnosis")
        report["status"] = "completed-diagnostic-only"
    except BaseException as error:
        report.update(status="interrupted-or-failed", error_type=type(error).__name__)
        raise
    finally:
        write(output / "report.json", report)


if __name__ == "__main__":
    main()
