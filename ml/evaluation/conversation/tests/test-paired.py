"""Correlated derivatives and relocated errors must not qualify a candidate."""

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
from ml.evaluation.conversation import paired  # noqa: E402


def row(key, *, partition="validation"):
    return dict(
        id=key,
        family=key,
        scenario_group=key,
        paraphrase_group=key,
        speaker_group=key,
        partition=partition,
        utterance=f"Bitte abbrechen, {key}.",
        provenance="agent-authored-invented-development",
        context=dict(today="2031-05-17", timezone="Europe/Vienna", visible_references=["one"]),
        expected={"action": "cancel"},
    )


def case(source, baseline=None, candidate=None):
    baseline = baseline if baseline is not None else source["expected"]
    candidate = candidate if candidate is not None else source["expected"]
    outputs = {
        name: json.dumps(baseline if name == "baseline" else candidate) for name in paired.PROVIDERS
    }
    return dict(
        id=source["id"],
        family=source["family"],
        expected=source["expected"],
        outputs=outputs,
        providers={name: paired.outcome(answer, source) for name, answer in outputs.items()},
        fusion_equal=True,
        runtime_equal=True,
    )


def report(cases):
    return dict(
        schema_version=1,
        kind="complete-greedy-development-answers",
        qualified=False,
        cases=cases,
        complete_text_parity=True,
        counts={
            name: {
                metric: sum(case["providers"][name][metric] for case in cases)
                for metric in paired.METRICS
            }
            for name in paired.PROVIDERS
        },
    )


class PairedTests(unittest.TestCase):
    def test_dependencies_are_transitive_and_namespaced(self):
        rows = [row(key) for key in ("a", "b", "c", "d")]
        rows[1]["family"] = "a"
        rows[2]["speaker_group"] = "b"
        rows[3]["paraphrase_group"] = "a"  # a family is not a paraphrase identity
        rows[0]["paraphrase_group"] = "different"
        self.assertEqual(paired.clusters(rows), [["a", "b", "c"], ["d"]])
        self.assertEqual(paired.clusters(list(reversed(rows))), paired.clusters(rows))

    def test_duplicate_or_missing_groups_are_rejected(self):
        for rows in ([], [row("a"), row("a")], [dict(row("a"), speaker_group="")]):
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                paired.clusters(rows)

    def test_shared_speaker_never_yields_false_independence_or_precision(self):
        rows = [dict(row(str(i)), speaker_group="invented-speaker") for i in range(40)]
        result = paired.summarize([case(source) for source in rows], paired.clusters(rows))
        self.assertEqual(len(result["dependency_components"]), 1)
        self.assertEqual(result["uncertainty"]["completed_draws"], 0)
        self.assertIsNone(result["metrics"]["exact_match"]["interval_95"])
        self.assertEqual(result["metrics"]["exact_match"]["denominator"], 40)

    def test_paired_resampling_preserves_whole_unequal_components(self):
        wrong = {"action": "help", "topic": "voice"}
        cases = [case(row("a"), baseline=wrong)] + [
            case(row(key), candidate=wrong) for key in ("b", "c", "d")
        ]
        result = paired.summarize(cases, [["a"], ["b", "c", "d"]], draws=1000)
        self.assertEqual(result["metrics"]["exact_match"]["delta"], -0.5)
        self.assertEqual(result["metrics"]["exact_match"]["interval_95"], [-1.0, 1.0])
        self.assertEqual(
            result, paired.summarize(list(reversed(cases)), [["d", "b", "c"], ["a"]], draws=1000)
        )

    def test_identical_models_have_zero_paired_difference(self):
        cases = [case(row(key)) for key in ("a", "b")]
        result = paired.summarize(cases, [["a"], ["b"]], draws=1000)
        for metric in paired.METRICS:
            self.assertEqual(result["metrics"][metric]["interval_95"], [0.0, 0.0])
        self.assertTrue(result["no_new_regressions"])

    def test_aggregate_improvement_does_not_hide_new_unsafe_operation(self):
        wrong = {"action": "help", "topic": "voice"}
        cases = [case(row(key), baseline=wrong) for key in ("a", "b", "c")]
        cases.append(case(row("d"), candidate={"action": "remove", "query": {"reference": "one"}}))
        result = paired.summarize(cases, [[case["id"]] for case in cases], draws=1000)
        self.assertGreater(result["metrics"]["exact_match"]["delta"], 0)
        self.assertFalse(result["no_new_regressions"])
        self.assertIn("new_unsafe_proposed_mutation", result["regressions"][0]["reasons"])
        self.assertEqual(result["regressions"][0]["id"], "d")

    def test_equal_error_totals_do_not_hide_a_changed_wrong_operation(self):
        cases = [
            case(
                row("a"),
                baseline={"action": "help", "topic": "voice"},
                candidate={"action": "help", "topic": "privacy"},
            )
        ]
        result = paired.summarize(cases, [["a"]])
        self.assertEqual(result["metrics"]["exact_match"]["delta"], 0)
        self.assertEqual(result["regressions"][0]["reasons"], ["changed_incorrect_operation"])

    def test_missing_duplicate_or_overlapping_pairs_fail(self):
        cases = [case(row("a")), case(row("b"))]
        for groups in ([], [["a"]], [["a", "b"], ["a"]], [["a", "other"]], [[], ["a", "b"]]):
            with self.subTest(groups=groups), self.assertRaises(ValueError):
                paired.summarize(cases, groups)

    def test_recorded_flags_and_complete_coverage_are_rechecked(self):
        rows = [row("a"), row("b")]
        original = report([case(source) for source in rows])
        self.assertEqual(len(paired.check_answers(original, rows)), 2)
        mutations = [
            lambda value: value["cases"].pop(),
            lambda value: value["cases"].append(value["cases"][0]),
            lambda value: value["cases"][0].update(family="changed"),
            lambda value: value["cases"][0].update(expected={"action": "help", "topic": "voice"}),
            lambda value: value["cases"][0]["providers"]["assistant"].update(exact_match=1),
            lambda value: value["cases"][0]["outputs"].update(
                assistant='{"action":"help","topic":"voice"}'
            ),
            lambda value: value["cases"][0].update(runtime_equal=False),
            lambda value: value["counts"]["baseline"].update(exact_match=0),
            lambda value: value.update(complete_text_parity=False),
        ]
        for mutate in mutations:
            changed = copy.deepcopy(original)
            mutate(changed)
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                paired.check_answers(changed, rows)

    def test_audit_checks_lineage_and_never_overwrites_or_qualifies(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            run = root / ".local/runs/source"
            (run / "deployment").mkdir(parents=True)

            def write(path, value):
                path.write_text(json.dumps(value))
                return paired.sha(path)

            sources = {}
            for name in (
                "ml/evaluation/conversation/intent.py",
                "ml/training/assistant/contract.py",
            ):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((ROOT / name).read_bytes())
                sources[name] = paired.sha(path)
            dataset = run / "data.json"
            data_hash = write(
                dataset,
                dict(
                    schema_version=1,
                    kind="invented-development-dialogues",
                    final_holdout=False,
                    independent_real_dialogues=0,
                    human_review="pending",
                    samples=[row("train", partition="train"), row("valid")],
                ),
            )
            settings_hash = write(run / "settings.json", dict(dataset=str(dataset)))
            identity_hash = write(
                run / "identity.json",
                dict(
                    settings_sha256=settings_hash,
                    lineage=dict(dataset_sha256=data_hash, sources_sha256=sources),
                ),
            )
            answers = dict(report([case(row("valid"))]), run_identity_sha256=identity_hash)
            answers_hash = write(run / "deployment/parity.json", answers)
            card = run / "card.json"
            write(
                card,
                dict(
                    run_identity_sha256=identity_hash,
                    dataset_sha256=data_hash,
                    deployment_complete_answer_parity=dict(report_sha256=answers_hash),
                ),
            )
            destination = root / ".local/runs/audit"
            with patch.object(paired, "ROOT", root):
                result = paired.audit(run, card, destination)
                self.assertFalse(result["qualified"])
                self.assertFalse(result["final_holdout"])
                with self.assertRaises(FileExistsError):
                    paired.audit(run, card, destination)
                with self.assertRaises(ValueError):
                    paired.audit(run, card, root / "tracked-output")
                dataset.write_text(dataset.read_text() + " ")
                with self.assertRaises(ValueError):
                    paired.audit(run, card, root / ".local/runs/changed")
                self.assertFalse((root / ".local/runs/changed").exists())


if __name__ == "__main__":
    unittest.main()
