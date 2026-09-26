"""Prepare and assess recorded native answers through the existing Swift router probe.

No model, compiler or calendar is started here. Preparation pins the same invented
cases and actual recorded prompts; scoring reuses the app evaluation contract.
"""

import argparse
import json
import re
import shlex
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from ml.evaluation.conversation.app_evaluation import evaluate, prepare  # noqa: E402
from ml.training.assistant.contract import messages, sha  # noqa: E402
from ml.training.assistant.export import clean_answer  # noqa: E402

VARIANTS = ("historical-app", "historical-cli", "corrected-cli")
SOURCES = (
    "Makefile",
    "Cargo.toml",
    "Cargo.lock",
    "rust-toolchain.toml",
    "config/storage/workspace.json",
    "config/toolchains/versions.json",
    "tooling/dev/workspace.py",
    "apps/ios/Features/Conversation/Resources/assistant-system-v1.txt",
    "ml/evaluation/conversation/fixtures/prompt-v1.json",
    "ml/evaluation/conversation/router_replay.py",
    "ml/evaluation/conversation/app_evaluation.py",
    "ml/evaluation/conversation/intent.py",
    "ml/evaluation/conversation/paired.py",
    "ml/training/assistant/contract.py",
    "ml/training/assistant/export.py",
    "ml/training/assistant/train.py",
    "ml/training/assistant/restore.py",
    "ml/training/storage.py",
)


def load(path):
    return json.loads(path.read_text())


def write(path, value):
    with path.open("x") as stream:
        stream.write(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n")


def source_paths():
    """Pin the compiler's shared Swift response file and its native dependencies."""
    paths = {ROOT / name for name in SOURCES}
    for name in ["test-custom-assistant-provider.sh", "test-calendar-answers.sh"]:
        script = ROOT / "tooling/checks" / name
        paths.add(script)
        text = script.read_text()
        # Include both the generated FFI wrapper and the selected/default probe.
        paths.update(
            ROOT / name for name in re.findall(r"(?:apps|packages)/[\w./-]+\.swift\b", text)
        )
        for name in re.findall(r"@([\w./-]+\.rsp)\b", text):
            response = ROOT / name
            paths.add(response)
            entries = shlex.split(response.read_text(), comments=True)
            if not entries:
                raise ValueError("Empty Swift compiler source response file")
            for entry in entries:
                source = (ROOT / entry).resolve()
                if (
                    not source.is_relative_to(ROOT)
                    or source.suffix != ".swift"
                    or not source.is_file()
                ):
                    raise ValueError("Invalid Swift compiler source response entry")
                paths.add(source)
    headers = ROOT / "packages/apple/RehaCore/Headers"
    paths.update(path for path in headers.rglob("*") if path.is_file())
    for name in ["reha-core", "reha-ffi"]:
        crate = ROOT / "packages/rust" / name
        paths.add(crate / "Cargo.toml")
        paths.update(path for path in (crate / "src").rglob("*") if path.is_file())
        if (crate / "build.rs").is_file():
            paths.add(crate / "build.rs")
    return sorted(paths)


def prepare_replay(app, deployment, native, output):
    fixture = load(app / "input.json")
    regenerated, rows = prepare(app / "dataset.json", fixture["run_id"], "custom")
    prior = load(deployment / "parity.json")
    trace = load(native / "report.json")
    original = load(app / "report.json")
    ids = [row["id"] for row in rows]
    if (
        fixture != regenerated
        or len(ids) != 40
        or [c["id"] for c in prior["cases"]] != ids
        or [c["id"] for c in trace["full_corpus_controls"]] != ids
        or [c["id"] for c in original["cases"]] != ids
        or original["dataset_sha256"] != sha(app / "dataset.json")
        or original["fixture_sha256"] != sha(app / "input.json")
        or trace["sources"][str((deployment / "parity.json").resolve())]
        != sha(deployment / "parity.json")
    ):
        raise ValueError("Recorded cases, fixture or source evidence changed")
    sources = [app / n for n in ["input.json", "dataset.json", "report.json"]]
    sources += [deployment / "parity.json", native / "report.json"]
    variants = [
        dict(id=name, model_identity=original["model_identity"], cases=[]) for name in VARIANTS
    ]
    for index, (row, old, control, app_case) in enumerate(
        zip(rows, prior["cases"], trace["full_corpus_controls"], original["cases"], strict=True)
    ):
        if any(
            c["expected"] != row["expected"] or c["family"] != row["family"]
            for c in [old, app_case]
        ):
            raise ValueError("Recorded targets differ from the fixed dataset")
        prompt = deployment / f"case-{index:04}.prompt.txt"
        recorded = native / f"case-{index:04}.desktop-auto.txt"
        text = prompt.read_text()
        expected_user = messages(row, include_answer=False)[1]["content"]
        if (
            trace["sources"][str(prompt.resolve())] != sha(prompt)
            or text.count("<|im_start|>user\n") != 1
            or text.split("<|im_start|>user\n", 1)[1].split("<|im_end|>", 1)[0] != expected_user
            or control["variants"]["desktop-auto"]["prompt_tokens_equal"] is not True
            or clean_answer(recorded.read_text()) != control["variants"]["desktop-auto"]["answer"]
        ):
            raise ValueError("Recorded request context or native output changed")
        sources.extend([prompt, recorded])
        base = {key: row[key] for key in ["id", "family", "expected"]}
        variants[0]["cases"].append(dict(base, observation=app_case["observation"]))
        for variant, response in zip(
            variants[1:], [old["outputs"]["assistant"], recorded.read_text()], strict=True
        ):
            variant["cases"].append(dict(base, raw_response=clean_answer(response)))
    output = output.resolve()
    if not output.is_relative_to(ROOT / ".local/runs"):
        raise ValueError("Keep replay artifacts below .local/runs")
    output.mkdir(parents=True, exist_ok=False)
    write(output / "input.json", fixture)
    write(output / "recorded.json", dict(variants=variants))
    write(
        output / "prepared.json",
        dict(
            schema_version=1,
            qualified=False,
            full_voice_workflow=False,
            fresh_inference=False,
            dataset=str((app / "dataset.json").resolve()),
            sources={str(p.resolve()): sha(p) for p in [*sources, *source_paths()]},
            inputs={name: sha(output / name) for name in ["input.json", "recorded.json"]},
            response_adaptation="Only outer whitespace and llama-completion's final display marker removed; JSON not parsed or rewritten",
        ),
    )


def assess(result, fixture, rows, recorded):
    if (
        result.get("kind") != "paired-recorded-synthetic-response-replay"
        or any(
            result.get(key) is not False
            for key in ["qualified", "fresh_inference", "full_voice_workflow"]
        )
        or [v.get("id") for v in result.get("variants", [])] != list(VARIANTS)
        or [v.get("id") for v in recorded["variants"]] != list(VARIANTS)
    ):
        raise ValueError("Incomplete or wrong-scope router replay")
    summaries = {}
    for observed, source in zip(result["variants"], recorded["variants"], strict=True):
        cases = observed["cases"]
        if [c["id"] for c in cases] != [r["id"] for r in rows] or any(
            c["expected"] != r["expected"] or c["family"] != r["family"]
            for c, r in zip(cases, rows, strict=True)
        ):
            raise ValueError("Replay cases or expected outcomes changed")
        observations = []
        for case in cases:
            if type(case.get("recorded_response_admitted")) is not bool:
                raise ValueError("Missing actual router admission observation")
            item = dict(id=case["id"], interpretation_seconds=0)
            if "operation" in case and "error" not in case:
                if case["provider"] not in {"complete-rules", "recorded-response"}:
                    raise ValueError("Unexpected interpretation provider")
                rules = case["provider"] == "complete-rules"
                if rules == case["recorded_response_admitted"]:
                    raise ValueError("Provider and recorded-answer admission disagree")
                item.update(
                    status="interpreted",
                    operation=case["operation"],
                    provider="complete-rules" if rules else "custom-qwen-trial",
                    model_identity="calendar-3" if rules else source["model_identity"],
                )
            elif "error" in case and "operation" not in case:
                item.update(status="error")
            else:
                raise ValueError("Ambiguous replay outcome")
            observations.append(item)
        admitted = sum(c["recorded_response_admitted"] for c in cases)
        if admitted != observed["recorded_responses_admitted"]:
            raise ValueError("Incorrect recorded-answer admission count")
        evaluation = evaluate(
            dict(
                run_id=fixture["run_id"],
                mode="custom",
                stage="evaluated",
                qualified=False,
                calendar_operations=0,
                provider="custom-qwen-trial",
                model_identity=source["model_identity"],
                cases=observations,
            ),
            fixture,
            rows,
            source["model_identity"],
        )
        evaluation.update(
            recorded_responses_admitted=admitted,
            timing_scope="No latency measurement; recorded text replay, no inference",
        )
        summaries[observed["id"]] = evaluation
    before, after = (summaries[name]["cases"] for name in ["historical-cli", "corrected-cli"])
    return dict(
        schema_version=1,
        qualified=False,
        fresh_inference=False,
        full_voice_workflow=False,
        independent_real_dialogues=0,
        variants=summaries,
        new_unsafe_proposed_mutations=[
            b["id"]
            for a, b in zip(before, after, strict=True)
            if b["unsafe_proposed_mutation"] and not a["unsafe_proposed_mutation"]
        ],
        new_incorrect_cases=[
            b["id"]
            for a, b in zip(before, after, strict=True)
            if a["exact_match"] and not b["exact_match"]
        ],
        assessment_scope="Same current Swift router, rules, native schema decoder and safety boundary; recorded-response telemetry mapped to the existing app scoring contract",
    )


def summarize(output):
    prepared = load(output / "prepared.json")
    for path, digest in prepared["sources"].items():
        if sha(Path(path)) != digest:
            raise ValueError(f"Replay source changed: {path}")
    for name, digest in prepared["inputs"].items():
        if sha(output / name) != digest:
            raise ValueError(f"Replay input changed: {name}")
    fixture = load(output / "input.json")
    _, rows = prepare(Path(prepared["dataset"]), fixture["run_id"], "custom")
    summary = assess(load(output / "router.json"), fixture, rows, load(output / "recorded.json"))
    summary["evidence"] = {name: sha(output / name) for name in ["prepared.json", "router.json"]}
    write(output / "summary.json", summary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=["prepare", "summarize"])
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--app", type=Path)
    parser.add_argument("--deployment", type=Path)
    parser.add_argument("--native", type=Path)
    args = parser.parse_args()
    if args.stage == "prepare":
        if any(path is None for path in [args.app, args.deployment, args.native]):
            parser.error("Preparation requires --app, --deployment and --native")
        prepare_replay(args.app, args.deployment, args.native, args.output)
    else:
        summarize(args.output)


if __name__ == "__main__":
    main()
