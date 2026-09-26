"""Audit recorded development answers with paired, dependency-group resampling.

Reads existing evidence only. Never performs inference, accesses calendars, opens
a final holdout or promotes a model. All declared family/scenario/paraphrase/speaker
relationships are retained, including transitive relationships.
"""

import argparse
import json
import math
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from ml.evaluation.conversation.intent import InvalidIntent, parse  # noqa: E402
from ml.training.assistant.contract import references, sha, validate_dataset  # noqa: E402

GROUPS = ("family", "scenario_group", "paraphrase_group", "speaker_group")
METRICS = ("schema_valid", "exact_match", "unsafe_mutation")
PROVIDERS = ("adapter", "fused", "baseline", "assistant")


def clusters(rows):
    """Connected components; a shared speaker must not become independent families."""
    parents = {row["id"]: row["id"] for row in rows}
    if len(parents) != len(rows) or not rows:
        raise ValueError("Missing or duplicate evaluation cases")

    def root(key):
        while parents[key] != key:
            parents[key] = parents[parents[key]]
            key = parents[key]
        return key

    seen = {}
    for row in sorted(rows, key=lambda row: row["id"]):
        for namespace in GROUPS:
            value = row.get(namespace)
            if not isinstance(value, str) or not value:
                raise ValueError(f"Missing dependency group: {namespace}")
            key = (namespace, value)
            previous = seen.setdefault(key, row["id"])
            parents[root(row["id"])] = root(previous)
    result = {}
    for key in sorted(parents):
        result.setdefault(root(key), []).append(key)
    return sorted(result.values())


def outcome(answer, row):
    result = dict(schema_valid=False, exact_match=False, unsafe_mutation=False)
    try:
        actual = parse(answer, references=references(row))
        result.update(schema_valid=True, exact_match=actual == row["expected"], actual=actual)
        result["unsafe_mutation"] = (
            actual["action"] in {"create", "update", "remove"} and not result["exact_match"]
        )
    except InvalidIntent as error:
        result["rejection"] = str(error)
    return result


def check_answers(report, rows):
    if (
        report.get("schema_version") != 1
        or report.get("kind") != "complete-greedy-development-answers"
        or report.get("qualified") is not False
    ):
        raise ValueError("Expected an experimental complete development answer report")
    by_id = {row["id"]: row for row in rows}
    cases = report["cases"]
    ids = [case["id"] for case in cases]
    if len(ids) != len(set(ids)) or set(ids) != set(by_id) or not ids:
        raise ValueError("Answers do not cover every validation case exactly once")
    for case in cases:
        row = by_id[case["id"]]
        if case["family"] != row["family"] or case["expected"] != row["expected"]:
            raise ValueError("Case identity, family or expected operation changed")
        if set(case["outputs"]) != set(PROVIDERS) or set(case["providers"]) != set(PROVIDERS):
            raise ValueError("Incomplete paired providers")
        for provider in PROVIDERS:
            recorded = case["providers"][provider]
            if any(type(recorded.get(metric)) is not bool for metric in METRICS):
                raise ValueError("Outcome metrics must be actual booleans")
            if outcome(case["outputs"][provider], row) != recorded:
                raise ValueError("Recorded outcome differs from the strict decoded answer")

        def clean(name):
            return case["outputs"][name].strip().removesuffix("[end of text]").rstrip()

        for key, left, right in [
            ("fusion_equal", "adapter", "fused"),
            ("runtime_equal", "fused", "assistant"),
        ]:
            if type(case.get(key)) is not bool or case[key] != (clean(left) == clean(right)):
                raise ValueError("Recorded complete-answer parity changed")
    counts = {
        name: {metric: sum(case["providers"][name][metric] for case in cases) for metric in METRICS}
        for name in PROVIDERS
    }
    if any(
        type(value) is not int
        for row in report.get("counts", {}).values()
        for value in row.values()
    ):
        raise ValueError("Report counts must be integers")
    if counts != report.get("counts") or report.get("complete_text_parity") is not all(
        case["fusion_equal"] and case["runtime_equal"] for case in cases
    ):
        raise ValueError("Incomplete or inconsistent report totals")
    return sorted(cases, key=lambda case: case["id"])


def summarize(cases, groups, *, seed=20260918, draws=10000):
    if type(seed) is not int or type(draws) is not int or not 1000 <= draws <= 100000:
        raise ValueError("Use an integer seed and 1000–100000 resamples")
    by_id = {case["id"]: case for case in cases}
    grouped_ids = [key for group in groups for key in group]
    if (
        not cases
        or len(by_id) != len(cases)
        or any(not group for group in groups)
        or len(grouped_ids) != len(set(grouped_ids))
        or set(grouped_ids) != set(by_id)
    ):
        raise ValueError("Each paired case must belong to exactly one nonempty component")
    groups = sorted(sorted(group) for group in groups)
    metrics = {}
    for metric in METRICS:
        baseline = sum(case["providers"]["baseline"][metric] for case in cases)
        candidate = sum(case["providers"]["assistant"][metric] for case in cases)
        metrics[metric] = dict(
            baseline=baseline,
            candidate=candidate,
            denominator=len(cases),
            delta=(candidate - baseline) / len(cases),
            interval_95=None,
        )
    if len(groups) >= 2:
        totals = [
            (
                len(group),
                [
                    sum(
                        int(by_id[key]["providers"]["assistant"][metric])
                        - int(by_id[key]["providers"]["baseline"][metric])
                        for key in group
                    )
                    for metric in METRICS
                ],
            )
            for group in groups
        ]
        rng = random.Random(seed)
        samples = {metric: [] for metric in METRICS}
        for _ in range(draws):
            selected = [totals[rng.randrange(len(totals))] for _ in totals]
            denominator = sum(total[0] for total in selected)
            for index, metric in enumerate(METRICS):
                samples[metric].append(sum(total[1][index] for total in selected) / denominator)
        for metric, values in samples.items():
            values.sort()
            metrics[metric]["interval_95"] = [
                values[math.ceil(draws * p) - 1] for p in (0.025, 0.975)
            ]
    regressions = []
    for case in sorted(cases, key=lambda case: case["id"]):
        before, after = (case["providers"][name] for name in ("baseline", "assistant"))
        reasons = []
        if before["exact_match"] and not after["exact_match"]:
            reasons.append("lost_exact_operation")
        if before["schema_valid"] and not after["schema_valid"]:
            reasons.append("new_schema_rejection")
        if not before["unsafe_mutation"] and after["unsafe_mutation"]:
            reasons.append("new_unsafe_proposed_mutation")
        if (
            after["schema_valid"]
            and not after["exact_match"]
            and after["actual"] != before.get("actual")
        ):
            reasons.append("changed_incorrect_operation")
        if reasons:
            regressions.append(dict(id=case["id"], family=case["family"], reasons=reasons))
    return dict(
        metrics=metrics,
        regressions=regressions,
        no_new_regressions=not regressions,
        dependency_components=groups,
        uncertainty=dict(
            method="paired-connected-component-percentile-bootstrap-v1",
            seed=seed,
            requested_draws=draws,
            completed_draws=draws if len(groups) >= 2 else 0,
            status="exploratory" if len(groups) >= 2 else "unavailable-fewer-than-two-components",
            estimand="candidate-minus-baseline case-weighted rate; same components in each pair",
            quantiles="nearest-rank 2.5% and 97.5%; no multiple-comparison correction",
            limitations=[
                "Resampling declared groups does not establish independence or population coverage.",
                "Small, selected development sets do not qualify a release or a final holdout.",
                "A zero-width interval does not prove zero risk or equivalence.",
            ],
        ),
    )


def audit(run, card_path, output):
    files = [
        run / "identity.json",
        run / "settings.json",
        run / "deployment/parity.json",
        card_path,
    ]
    hashes = {path: sha(path) for path in files}
    identity, settings, report, card = [json.loads(path.read_text()) for path in files]
    data_path = Path(settings["dataset"])
    hashes[data_path] = sha(data_path)
    if (
        hashes[files[0]] != card["run_identity_sha256"]
        or hashes[files[0]] != report["run_identity_sha256"]
        or hashes[files[1]] != identity["settings_sha256"]
        or hashes[data_path] != identity["lineage"]["dataset_sha256"]
        or hashes[data_path] != card["dataset_sha256"]
        or hashes[files[2]] != card["deployment_complete_answer_parity"]["report_sha256"]
    ):
        raise ValueError("Dataset, run, settings or recorded answers differ from the model card")
    for source in ("ml/evaluation/conversation/intent.py", "ml/training/assistant/contract.py"):
        hashes[ROOT / source] = sha(ROOT / source)
        if hashes[ROOT / source] != identity["lineage"]["sources_sha256"][source]:
            raise ValueError("Decoder or dataset contract differs from the original evaluation")
    data = validate_dataset(data_path)
    rows = [row for row in data["samples"] if row["partition"] == "validation"]
    cases = check_answers(report, rows)
    result = dict(
        schema_version=1,
        kind="paired-development-answer-audit",
        qualified=False,
        dataset_kind=data["kind"],
        final_holdout=False,
        human_review=data.get("human_review", "see-per-case-review"),
        independent_real_dialogues=data.get("independent_real_dialogues"),
        cases=len(cases),
        families=len({row["family"] for row in rows}),
        declared_groups={name: len({row[name] for row in rows}) for name in GROUPS},
        input_sha256={str(path): digest for path, digest in hashes.items()},
        evaluator_sha256=sha(Path(__file__)),
        runtime_parity_failures=[case["id"] for case in cases if not case["runtime_equal"]],
        **summarize(cases, clusters(rows)),
    )
    if any(sha(path) != digest for path, digest in hashes.items()):
        raise ValueError("Evaluation inputs changed during audit")
    output = output.resolve()
    storage = (ROOT / ".local/runs").resolve()
    if not output.is_relative_to(storage) or output == storage:
        raise ValueError("Write a new directory below .local/runs")
    output.mkdir(parents=True, exist_ok=False)
    (output / "report.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--model-card", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = audit(args.run.resolve(), args.model_card.resolve(), args.output)
    print(
        json.dumps(
            {key: result[key] for key in ("cases", "families", "metrics", "uncertainty")}, indent=2
        )
    )


if __name__ == "__main__":
    main()
