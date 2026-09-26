"""Diagnose retained MLX/GGUF answer differences at identical token prefixes."""

import argparse
import ast
import gc
import hashlib
import importlib.metadata
import json
import os
import re
import resource
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def save(path, value):
    with path.open("x") as stream:
        stream.write(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n")


def first_difference(left, right):
    for index, (a, b) in enumerate(zip(left, right)):
        if a != b:
            return index
    return min(len(left), len(right)) if len(left) != len(right) else None


def validate_requests(requests):
    if not isinstance(requests, list) or not 1 <= len(requests) <= 40:
        raise ValueError("Expected one to forty retained cases")
    seen = set()
    for request in requests:
        identity = request.get("id")
        limit = request.get("max_tokens")
        if (
            not isinstance(identity, str)
            or not identity
            or any(c not in "0123456789" for c in identity)
            or identity in seen
            or not isinstance(request.get("prompt"), str)
            or type(limit) is not int
            or not 1 <= limit <= 256
        ):
            raise ValueError("Invalid diagnostic case identity or token limit")
        seen.add(identity)
        if "prefix" in request:
            prefix = request["prefix"]
            if (
                not isinstance(prefix, list)
                or limit != len(prefix) + 1
                or any(type(t) is not int or t < 0 for t in prefix)
            ):
                raise ValueError("Invalid bounded teacher-forced prefix")


def forced_request(request, left, right):
    if left["input_tokens"] != right["input_tokens"]:
        raise ValueError("Prompt tokenization differs; do not compare continuation logits")
    position = first_difference(left["tokens"], right["tokens"])
    if position is None:
        raise ValueError("Retained failure no longer has a token difference")
    if position >= min(len(left["tokens"]), len(right["tokens"])):
        raise ValueError("A trace ended without recording its differing stop token")
    return {
        **request,
        "prefix": left["tokens"][:position],
        "max_tokens": position + 1,
    }


def cli_token_ids(stderr):
    """Read actual CLI tokens, not merely the length of the rendered template."""
    heading = re.search(r"number of tokens in prompt = (\d+)\n", stderr)
    if heading is None:
        raise ValueError("CLI did not report its actual prompt tokens")
    expected = int(heading.group(1))
    tokens = [int(t) for t in re.findall(r"^\s*(\d+) -> '", stderr[heading.end() :], re.M)]
    if len(tokens) != expected:
        raise ValueError("Incomplete or ambiguous CLI prompt token evidence")
    return tokens


def historical_file_command(arguments):
    """Explicit counterfactual only: reproduce the retained, lossy -f route."""
    result = list(arguments)
    result[result.index("--binary-file")] = "-f"
    result.remove("--no-escape")
    return result


def rankings(values):
    import numpy as np

    values = np.asarray(values).reshape(-1)
    if not np.isfinite(values).all() or len(values) < 10:
        raise ValueError("Invalid diagnostic logits")
    boundary = np.partition(values, -10)[-10]
    candidates = np.flatnonzero(values >= boundary)
    order = np.lexsort((candidates, -values[candidates]))[:10]
    return [{"token": int(i), "logit": float(values[i])} for i in candidates[order]]


def mlx_worker(model_path, requests, output):
    validate_requests(requests)
    output = output.resolve()
    if not output.is_relative_to(ROOT / ".local/runs") or output.exists():
        raise ValueError("Use a new private worker directory")
    for request in requests:
        prompt_path = Path(request["prompt"])
        if not prompt_path.is_file() or prompt_path.stat().st_size > 100000:
            raise ValueError("Invalid diagnostic prompt file")
    import mlx.core as mx
    import numpy as np
    from mlx_lm import generate
    from mlx_lm.generate import generate_step
    from mlx_lm.sample_utils import make_sampler
    from mlx_lm.utils import load

    output.mkdir(mode=0o700)
    # Limit reclaimable allocator caching, not model arithmetic or KV precision.
    mx.set_cache_limit(64 * 1024 * 1024)
    model, tokenizer = load(str(model_path), tokenizer_config={"trust_remote_code": False})
    model.eval()
    report = {"diagnostic": True, "qualified": False, "cases": []}
    for request in requests:
        started = time.monotonic()
        prompt = Path(request["prompt"]).read_text()
        special = tokenizer.bos_token is None or not prompt.startswith(tokenizer.bos_token)
        input_tokens = tokenizer.encode(prompt, add_special_tokens=special)
        if len(input_tokens) + request["max_tokens"] > 2048:
            raise ValueError("Diagnostic context limit exceeded")
        prefix = request.get("prefix")
        control = None
        if prefix is None:
            control = generate(
                model,
                tokenizer,
                prompt=prompt,
                sampler=make_sampler(temp=0),
                max_tokens=request["max_tokens"],
                verbose=False,
            )
        observed, sampled = [], []

        def capture(_, logits):
            values = np.asarray(logits.astype(mx.float32)).reshape(-1)
            record = {
                "logits_dtype": str(logits.dtype),
                "top": rankings(values),
                "maximum_ties": int(np.count_nonzero(values == values.max())),
            }
            if prefix is not None and len(observed) == len(prefix):
                filename = f"case-{request['id']}.logits.f32"
                with (output / filename).open("xb") as stream:
                    stream.write(values.astype("<f4", copy=False).tobytes())
                record["logits_file"] = filename
            observed.append(record)
            return logits

        def sampler(logprobs):
            greedy = mx.argmax(logprobs, axis=-1)
            index = len(sampled)
            chosen = (
                mx.array([prefix[index]]) if prefix is not None and index < len(prefix) else greedy
            )
            sampled.append({"greedy": int(greedy.item()), "selected": int(chosen.item())})
            return chosen

        tokens = []
        iterator = generate_step(
            mx.array(input_tokens),
            model,
            max_tokens=request["max_tokens"],
            sampler=sampler,
            logits_processors=[capture],
        )
        for token, _ in iterator:
            tokens.append(token)
            if token in tokenizer.eos_token_ids:
                break
        iterator.close()
        eos = bool(tokens and tokens[-1] in tokenizer.eos_token_ids)
        text = tokenizer.decode(tokens[:-1] if eos else tokens)
        result = {
            "id": request["id"],
            "input_tokens": input_tokens,
            "tokens": tokens,
            "steps": [{**a, **b} for a, b in zip(observed[: len(tokens)], sampled, strict=False)],
            "text": text,
            "eos": eos,
            "control": control,
            "instrumentation_preserves_answer": control is None or control == text,
            "elapsed_seconds": time.monotonic() - started,
        }
        if prefix is not None:
            result["logits_file"] = observed[len(prefix)]["logits_file"]
        report["cases"].append(result)
        print(f"Traced MLX case {request['id']}", flush=True)
        gc.collect()
        mx.clear_cache()
    report["host_peak_rss_bytes"] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    report["mlx_peak_memory_bytes"] = mx.get_peak_memory()
    save(output / "report.json", report)


def source_cases(run, weights_evidence):
    sys.path.insert(0, str(ROOT))
    from transformers import AutoTokenizer

    from ml.training.assistant.contract import messages
    from ml.training.assistant.export import BASE, CONVERTER, RUNTIME, selected_checkpoint

    settings, data, checkpoint = selected_checkpoint(run)
    deployment = run / "deployment"
    prior = json.loads((deployment / "parity.json").read_text())
    export = json.loads((deployment / "export.json").read_text())
    receipt_path = RUNTIME.parent.parent / "receipt.json"
    receipt = json.loads(receipt_path.read_text())
    registry = json.loads((ROOT / "ml/registry/assistant-base.json").read_text())
    revision = subprocess.check_output(
        ["git", "-C", str(CONVERTER), "rev-parse", "HEAD"], text=True
    ).strip()
    dirty = subprocess.check_output(
        ["git", "-C", str(CONVERTER), "status", "--porcelain"], text=True
    ).strip()
    if (
        revision != registry["converter_revision"]
        or dirty
        or export["runtime_sha256"] != sha(RUNTIME)
        or receipt["runtime_sha256"] != sha(RUNTIME)
        or receipt["source_revision"] != registry["converter_revision"]
        or export["converter_revision"] != registry["converter_revision"]
        or export["run_identity_sha256"] != sha(run / "identity.json")
        or export["checkpoint_sha256"] != sha(checkpoint / "checkpoint.json")
        or any(
            export["artifacts"][name] != sha(deployment / name)
            for name in ["assistant.gguf", "parity.json"]
        )
    ):
        raise ValueError("Retained export evidence changed")
    weight_check = json.loads(weights_evidence.read_text())
    for name in [deployment / "fused/model.safetensors", deployment / "assistant.gguf"]:
        if weight_check["source_identities"][str(name.relative_to(ROOT))] != sha(name):
            raise ValueError("Model differs from the retained tensor comparison")
    rows = [row for row in data["samples"] if row["partition"] == "validation"]
    if [c["id"] for c in prior["cases"]] != [r["id"] for r in rows]:
        raise ValueError("Prior evaluation does not cover complete validation")
    tokenizer = AutoTokenizer.from_pretrained(
        str(BASE), trust_remote_code=False, local_files_only=True
    )
    requests, selected = [], []
    for index, (case, row) in enumerate(zip(prior["cases"], rows, strict=True)):
        if case["expected"] != row["expected"] or case["family"] != row["family"]:
            raise ValueError("Retained targets changed")
        prompt = deployment / f"case-{index:04}.prompt.txt"
        expected = tokenizer.apply_chat_template(
            messages(row, include_answer=False),
            tokenize=False,
            add_generation_prompt=True,
            enable_thinking=False,
        )
        if prompt.read_text() != expected:
            raise ValueError("Retained prompt differs from verified data")
        requests.append(
            {
                "id": f"{index:04}",
                "prompt": str(prompt),
                "max_tokens": settings["max_output_tokens"],
                "input_tokens": tokenizer.encode(expected),
            }
        )
        selected.append(case)
    if len(requests) != 40 or sum(not c["runtime_equal"] for c in selected) != 6:
        raise ValueError("Expected all forty retained cases, including the six failures")
    validate_requests(requests)
    sources = [
        *deployment.joinpath("fused").glob("*"),
        deployment / "assistant.gguf",
        deployment / "parity.json",
        deployment / "export.json",
        run / "identity.json",
        run / "settings.json",
        checkpoint / "checkpoint.json",
        receipt_path,
        RUNTIME,
        weights_evidence,
        weights_evidence.with_suffix(".py"),
        Path(__file__),
        Path(__file__).with_name("token_trace.cpp"),
        Path(__file__).with_name("runtime_parity.py"),
        Path(__file__).with_name("runtime_prompt.py"),
        ROOT / "ml/training/assistant/export.py",
        ROOT / ".local/upstream/llama.cpp/include/llama.h",
        ROOT / ".local/upstream/llama.cpp/common/arg.cpp",
        Path(settings["dataset"]),
        *[Path(r["prompt"]) for r in requests],
        *RUNTIME.parent.glob("*.dylib"),
    ]
    distribution = importlib.metadata.distribution("mlx-lm")
    sources.extend(
        distribution.locate_file(name)
        for name in [
            "mlx_lm/generate.py",
            "mlx_lm/sample_utils.py",
            "mlx_lm/tokenizer_utils.py",
            "mlx_lm/models/qwen3.py",
            "mlx_lm/models/base.py",
            "mlx_lm/models/cache.py",
        ]
    )
    return settings, requests, selected, {str(p.resolve()): sha(p) for p in sources if p.is_file()}


def invoke(arguments, log, *, env, timeout=900, stdout_path=None):
    with log.open("x") as stream:
        if stdout_path is None:
            subprocess.run(
                arguments,
                cwd=ROOT,
                env=env,
                stdout=stream,
                stderr=subprocess.STDOUT,
                check=True,
                timeout=timeout,
            )
        else:
            with stdout_path.open("x") as stdout:
                subprocess.run(
                    arguments,
                    cwd=ROOT,
                    env=env,
                    stdout=stdout,
                    stderr=stream,
                    check=True,
                    timeout=timeout,
                )


def reusable_worker_source(previous, current):
    names = {"sha", "save", "validate_requests", "rankings", "mlx_worker"}

    def contract(source):
        parsed = ast.parse(source)
        found = {
            node.name: ast.dump(node, include_attributes=False)
            for node in parsed.body
            if isinstance(node, ast.FunctionDef) and node.name in names
        }
        if set(found) != names:
            raise ValueError("Incomplete retained MLX worker source")
        return found

    if contract(previous) != contract(current):
        raise ValueError("MLX worker implementation changed; repeat generation")


def restore_mlx(previous, output, identities, requests):
    previous = previous.resolve(strict=True)
    if not previous.is_relative_to(ROOT / ".local/runs"):
        raise ValueError("Reuse only a retained private diagnostic run")
    old_sources = json.loads((previous / "sources.json").read_text())["sources"]
    own_source = str(Path(__file__).resolve())
    if old_sources.get(own_source) != sha(previous / "token_parity.py"):
        raise ValueError("Retained diagnostic source was modified")
    reusable_worker_source((previous / "token_parity.py").read_text(), Path(__file__).read_text())
    if {k: v for k, v in old_sources.items() if k != own_source} != {
        k: v for k, v in identities.items() if k != own_source
    }:
        raise ValueError("Model, environment or other source identities changed")
    if json.loads((previous / "requests.json").read_text()) != requests:
        raise ValueError("Retained worker requests differ from the full corpus")
    report_path = previous / "mlx/report.json"
    report = json.loads(report_path.read_text())
    if [r["id"] for r in report["cases"]] != [r["id"] for r in requests]:
        raise ValueError("Retained MLX worker did not finish every requested case")
    report["reused_from"] = str(report_path)
    (output / "mlx").mkdir(mode=0o700)
    save(output / "mlx/report.json", report)
    reused = [
        previous / "sources.json",
        previous / "token_parity.py",
        previous / "requests.json",
        report_path,
    ]
    identities.update({str(path): sha(path) for path in reused})
    return report


def diagnose(args):
    import numpy as np

    from ml.evaluation.conversation.runtime_parity import command
    from ml.training.assistant.export import CONVERTER, RUNTIME, clean_answer

    run, output = args.run.resolve(strict=True), args.output.resolve()
    if not output.is_relative_to(ROOT / ".local/runs") or output.exists():
        raise ValueError("Use a new private run directory; earlier evidence remains immutable")
    settings, requests, prior, identities = source_cases(
        run, args.weights_evidence.resolve(strict=True)
    )
    output.mkdir(mode=0o700)
    for source in [Path(__file__), Path(__file__).with_name("token_trace.cpp")]:
        shutil.copyfile(source, output / source.name)
    save(output / "requests.json", requests)
    env = {k: v for k, v in os.environ.items() if not k.startswith("LLAMA_ARG_")}
    if args.reuse_mlx:
        mlx = restore_mlx(args.reuse_mlx, output, identities, requests)
    else:
        invoke(
            [
                sys.executable,
                str(Path(__file__)),
                "--mlx-worker",
                str(run / "deployment/fused"),
                "--requests",
                str(output / "requests.json"),
                "--output",
                str(output / "mlx"),
            ],
            output / "mlx.log",
            env=env,
        )
        mlx = json.loads((output / "mlx/report.json").read_text())
    save(output / "sources.json", {"diagnostic": True, "qualified": False, "sources": identities})
    controls, unresolved = [], []
    # Full original desktop corpus first. Instrument only actual remaining disagreements.
    for request, case, left in zip(requests, prior, mlx["cases"], strict=True):
        if request["id"] != left["id"] or request["input_tokens"] != left["input_tokens"]:
            raise ValueError("Actual MLX prompt token identities differ")
        if not left["instrumentation_preserves_answer"] or clean_answer(
            left["text"]
        ) != clean_answer(case["outputs"]["fused"]):
            raise ValueError("MLX instrumentation or retained answer changed")
        arguments = command(
            RUNTIME,
            run / "deployment/assistant.gguf",
            Path(request["prompt"]),
            "desktop-auto",
            settings,
        )
        arguments.append("--verbose-prompt")
        control = output / f"case-{request['id']}.desktop-auto.txt"
        started = time.monotonic()
        invoke(arguments, control.with_suffix(".stderr"), stdout_path=control, env=env, timeout=120)
        answer = clean_answer(control.read_text())
        actual_ids = cli_token_ids(control.with_suffix(".stderr").read_text())
        if actual_ids != request["input_tokens"]:
            raise ValueError("Corrected CLI did not receive byte-equivalent prompt tokens")
        record = {
            "id": case["id"],
            "prompt_token_count": len(left["input_tokens"]),
            "historical_runtime_equal": case["runtime_equal"],
            "variants": {
                "desktop-auto": {
                    "command": arguments,
                    "elapsed_seconds": time.monotonic() - started,
                    "actual_input_tokens": actual_ids,
                    "prompt_tokens_equal": True,
                    "equals_fused": answer == clean_answer(left["text"]),
                    "answer": answer,
                }
            },
        }
        if not case["runtime_equal"]:
            arguments = historical_file_command(arguments)
            historical = output / f"case-{request['id']}.historical.txt"
            invoke(
                arguments,
                historical.with_suffix(".stderr"),
                stdout_path=historical,
                env=env,
                timeout=120,
            )
            if clean_answer(historical.read_text()) != clean_answer(case["outputs"]["assistant"]):
                raise ValueError("Historical CLI control changed")
            ids = cli_token_ids(historical.with_suffix(".stderr").read_text())
            position = first_difference(request["input_tokens"], ids)
            if position is None:
                raise ValueError("Expected the retained lossy CLI prompt boundary")
            record["historical_control"] = {
                "answer_reproduced": True,
                "command": arguments,
                "actual_input_tokens": ids,
                "first_input_difference": position,
                "expected_token": request["input_tokens"][position],
                "actual_token": ids[position],
            }
        if not record["variants"]["desktop-auto"]["equals_fused"]:
            unresolved.append((request, case, left, record))
        # Complete cases survive a later timeout; earlier records are never overwritten.
        save(output / f"case-{request['id']}.control.json", record)
        controls.append(record)
        print(f"Controlled full-corpus case {request['id']}", flush=True)
    save(output / "controls.json", controls)
    helper = output / "token-trace"
    compile_command = [
        "xcrun",
        "clang++",
        "-std=c++17",
        "-O2",
        "-Wall",
        "-Wextra",
        "-Werror",
        str(Path(__file__).with_name("token_trace.cpp")),
        "-I",
        str(CONVERTER / "include"),
        "-I",
        str(CONVERTER / "ggml/include"),
        "-I",
        str(CONVERTER / "vendor/nlohmann"),
        "-L",
        str(RUNTIME.parent),
        "-lllama",
        "-lggml",
        "-lggml-base",
        "-Wl,-rpath," + str(RUNTIME.parent),
        "-o",
        str(helper),
    ]
    forced, differing = [], []
    cpu = left_forced = right_forced = {"cases": []}
    if unresolved:
        invoke(compile_command, output / "compile.log", env=env, timeout=300)
        # Each small package stays below the per-process deadline under host pressure.
        for offset in range(0, len(unresolved), 4):
            group = unresolved[offset : offset + 4]
            request_path = output / f"unresolved-{offset:04}.json"
            save(request_path, [row[0] for row in group])
            worker_path = output / f"cpu-{offset:04}"
            invoke(
                [
                    str(helper),
                    str(run / "deployment/assistant.gguf"),
                    str(request_path),
                    str(worker_path),
                ],
                output / f"cpu-{offset:04}.log",
                env=env,
            )
            result = json.loads((worker_path / "report.json").read_text())
            cpu["host_peak_rss_bytes"] = max(
                cpu.get("host_peak_rss_bytes", 0), result["host_peak_rss_bytes"]
            )
            cpu["cases"].extend(result["cases"])
        for (request, case, left, record), right in zip(unresolved, cpu["cases"], strict=True):
            if request["id"] != right["id"] or request["input_tokens"] != right["input_tokens"]:
                raise ValueError("C-API context differs from the verified CLI prompt")
            arguments = command(
                RUNTIME,
                run / "deployment/assistant.gguf",
                Path(request["prompt"]),
                "cpu-native-batch",
                settings,
            )
            arguments.append("--verbose-prompt")
            control = output / f"case-{request['id']}.cpu-native-batch.txt"
            invoke(
                arguments, control.with_suffix(".stderr"), stdout_path=control, env=env, timeout=120
            )
            answer = clean_answer(control.read_text())
            if cli_token_ids(control.with_suffix(".stderr").read_text()) != request[
                "input_tokens"
            ] or answer != clean_answer(right["text"]):
                raise ValueError("C-API trace differs from the uninstrumented CPU control")
            if answer != record["variants"]["desktop-auto"]["answer"]:
                raise ValueError("Desktop and CPU differ; do not attribute desktop logits to CPU")
            forced.append(forced_request(request, left, right))
            differing.append((case, left, right))
        save(output / "forced.json", forced)
        invoke(
            [
                sys.executable,
                str(Path(__file__)),
                "--mlx-worker",
                str(run / "deployment/fused"),
                "--requests",
                str(output / "forced.json"),
                "--output",
                str(output / "mlx-forced"),
            ],
            output / "mlx-forced.log",
            env=env,
        )
        invoke(
            [
                str(helper),
                str(run / "deployment/assistant.gguf"),
                str(output / "forced.json"),
                str(output / "cpu-forced"),
            ],
            output / "cpu-forced.log",
            env=env,
        )
        left_forced = json.loads((output / "mlx-forced/report.json").read_text())
        right_forced = json.loads((output / "cpu-forced/report.json").read_text())
    report = {
        "schema_version": 1,
        "kind": "assistant-token-parity-diagnostic",
        "qualified": False,
        "diagnostic": True,
        "physical_device": False,
        "shipping_ios_route": False,
        "independent_new_cases": 0,
        "sources": identities,
        "compile_command": compile_command if unresolved else None,
        "helper_sha256": sha(helper) if unresolved else None,
        "packages": {
            k: importlib.metadata.version(k) for k in ["mlx", "mlx-lm", "numpy", "transformers"]
        },
        "workers": {
            name: {k: v for k, v in value.items() if k != "cases"}
            for name, value in [
                ("mlx", mlx),
                ("cpu", cpu),
                ("mlx-forced", left_forced),
                ("cpu-forced", right_forced),
            ]
        },
        "full_corpus_controls": controls,
        "full_corpus_summary": {
            "cases": len(controls),
            "historical_failures": sum(not c["runtime_equal"] for c in prior),
            "corrected_desktop_failures": len(unresolved),
            "new_desktop_failures": sum(
                c["historical_runtime_equal"] and not c["variants"]["desktop-auto"]["equals_fused"]
                for c in controls
            ),
            "cpu_controls": len(unresolved),
        },
        "cases": [],
    }
    for (case, original_l, original_r), request, left, right in zip(
        differing, forced, left_forced["cases"], right_forced["cases"], strict=True
    ):
        position = len(request["prefix"])
        if (
            left["id"] != request["id"]
            or right["id"] != request["id"]
            or left["input_tokens"] != right["input_tokens"]
            or left["tokens"][:-1] != request["prefix"]
            or right["tokens"][:-1] != request["prefix"]
            or [s["greedy"] for s in left["steps"][:position]] != request["prefix"]
            or [s["greedy"] for s in right["steps"][:position]] != request["prefix"]
        ):
            raise ValueError("Forced-prefix comparison changed context")
        if (
            left["steps"][position]["top"] != original_l["steps"][position]["top"]
            or right["steps"][position]["top"] != original_r["steps"][position]["top"]
        ):
            raise ValueError("Teacher-forced replay changed original next-token logits")
        a_path, b_path = (
            output / "mlx-forced" / left["logits_file"],
            output / "cpu-forced" / right["logits_file"],
        )
        a, b = np.fromfile(a_path, dtype="<f4"), np.fromfile(b_path, dtype="<f4")
        if a.shape != b.shape or not np.isfinite(a).all() or not np.isfinite(b).all():
            raise ValueError("Invalid matching-prefix logit arrays")
        chosen_l, chosen_r = original_l["tokens"][position], original_r["tokens"][position]
        report["cases"].append(
            {
                "id": case["id"],
                "prompt_tokens_equal": True,
                "prompt_token_count": len(left["input_tokens"]),
                "uninstrumented_answers_preserved": True,
                "historical_mlx_answer_reproduced": True,
                "first_token_difference": position,
                "mlx_token": chosen_l,
                "cpu_token": chosen_r,
                "mlx_top": left["steps"][position]["top"],
                "cpu_top": right["steps"][position]["top"],
                "mlx_maximum_ties": left["steps"][position]["maximum_ties"],
                "mlx_logits_dtype": left["steps"][position]["logits_dtype"],
                "cross_candidate_logits": {
                    "mlx": [float(a[chosen_l]), float(a[chosen_r])],
                    "cpu": [float(b[chosen_l]), float(b[chosen_r])],
                },
                "logit_max_absolute_difference": float(np.max(np.abs(a - b))),
                "forced_replay_preserves_top_logits": True,
                "logits_sha256": {"mlx": sha(a_path), "cpu": sha(b_path)},
            }
        )
    if identities != {path: sha(Path(path)) for path in identities}:
        raise ValueError("Source evidence changed during diagnosis")
    report["status"] = "diagnosed-not-qualified"
    save(output / "report.json", report)
    print("Token/logit diagnosis complete; no model or qualification rule changed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--weights-evidence", type=Path)
    parser.add_argument(
        "--reuse-mlx",
        type=Path,
        help="Reuse a completed MLX worker after exact source/input identity checks",
    )
    parser.add_argument("--mlx-worker", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--requests", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    os.environ.update(HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1", TOKENIZERS_PARALLELISM="false")
    sys.path.insert(0, str(ROOT))
    if args.mlx_worker:
        if not args.requests:
            parser.error("Worker requires requests")
        mlx_worker(args.mlx_worker, json.loads(args.requests.read_text()), args.output)
    else:
        if not args.run or not args.weights_evidence:
            parser.error("Provide run and retained tensor-comparison evidence")
        diagnose(args)


if __name__ == "__main__":
    main()
