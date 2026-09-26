"""Complete app observation coverage, context fidelity and unsafe-proposal regressions."""

import copy
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
from ml.evaluation.conversation.app_evaluation import (  # noqa: E402
    RULES_MODEL_IDENTITY,
    evaluate,
    prepare,
)
from ml.training.assistant.prepare import examples  # noqa: E402


class AppEvaluationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "dataset.json"
        self.data = dict(
            schema_version=1,
            kind="invented-development-dialogues",
            final_holdout=False,
            samples=examples(0, 20260917),
        )
        self.path.write_text(json.dumps(self.data))
        self.fixture, self.rows = prepare(self.path, "current", "custom")
        self.result = dict(
            run_id="current",
            mode="custom",
            stage="evaluated",
            qualified=False,
            calendar_operations=0,
            provider="custom-qwen-trial",
            model_identity="pinned",
            cases=[
                dict(
                    id=r["id"],
                    status="interpreted",
                    provider="custom-qwen-trial",
                    model_identity="pinned",
                    interpretation_seconds=0.5,
                    operation=r["expected"],
                )
                for r in self.rows
            ],
        )

    def audit(self, result=None):
        return evaluate(result or self.result, self.fixture, self.rows, "pinned")

    def test_targets_do_not_enter_the_app_and_correlated_cases_remain_grouped(self):
        self.assertNotIn("expected", json.dumps(self.fixture))
        result = self.audit()
        self.assertEqual(result["exact_matches"], len(self.rows))
        self.assertEqual(len(result["dependency_components"]), 1)
        self.assertFalse(result["qualified"])

    def test_lossy_context_and_final_holdout_are_rejected(self):
        for extra in [{"history": []}, {"selected": None}]:
            changed = copy.deepcopy(self.data)
            next(r for r in changed["samples"] if r["partition"] == "validation")["context"].update(
                extra
            )
            self.path.write_text(json.dumps(changed))
            with self.assertRaises(ValueError):
                prepare(self.path, "current", "custom")
        self.data["final_holdout"] = True
        self.path.write_text(json.dumps(self.data))
        with self.assertRaises(ValueError):
            prepare(self.path, "current", "custom")

    def test_stale_partial_reordered_and_duplicate_answers_are_rejected(self):
        for field, value in [
            ("run_id", "old"),
            ("mode", "apple"),
            ("stage", "interpreting"),
            ("qualified", True),
            ("calendar_operations", False),
            ("calendar_operations", 1),
            ("provider", "complete-rules"),
            ("model_identity", "other"),
            ("cases", self.result["cases"][:-1]),
            ("cases", list(reversed(self.result["cases"]))),
            ("cases", [self.result["cases"][0]] * len(self.rows)),
            ("cases", [None]),
        ]:
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                self.audit(dict(self.result, **{field: value}))

    def test_unsafe_operations_remain_visible_even_with_unrepresentable_constraints(self):
        changed = copy.deepcopy(self.result)
        changed["cases"][0]["operation"] = dict(
            action="remove", query=dict(reference="termin-1", title="unexpected filter")
        )
        result = self.audit(changed)
        self.assertEqual(result["unsafe_proposed_mutations"], 1)
        self.assertFalse(result["cases"][0]["schema_valid"])
        self.assertEqual(result["exact_matches"], len(self.rows) - 1)

    def test_unavailability_and_rejection_do_not_count_as_interpretations(self):
        changed = copy.deepcopy(self.result)
        for index, status in enumerate(["unavailable", "error"]):
            changed["cases"][index] = dict(
                id=self.rows[index]["id"], status=status, interpretation_seconds=0.1
            )
        result = self.audit(changed)
        self.assertEqual(result["status_counts"]["unavailable"], 1)
        self.assertEqual(result["status_counts"]["error"], 1)
        self.assertEqual(result["exact_matches"], len(self.rows) - 2)
        changed["cases"][0]["operation"] = {"action": "cancel"}
        with self.assertRaises(ValueError):
            self.audit(changed)

    def test_rules_fallback_preserves_its_own_identity(self):
        changed = copy.deepcopy(self.result)
        changed["cases"][0].update(provider="complete-rules", model_identity=RULES_MODEL_IDENTITY)
        self.audit(changed)
        changed["cases"][0]["model_identity"] = "pinned"
        with self.assertRaises(ValueError):
            self.audit(changed)

    def test_current_swift_rule_identity_is_accepted_and_stale_rules_are_rejected(self):
        source = (
            Path(__file__).resolve().parents[4]
            / "apps/ios/Features/Conversation/InterpretationProvider.swift"
        )
        identity = re.search(
            r'provider: "complete-rules", model: "([^"]+)"', source.read_text()
        ).group(1)
        self.assertEqual(RULES_MODEL_IDENTITY, identity)
        changed = copy.deepcopy(self.result)
        changed["cases"][0].update(provider="complete-rules", model_identity=identity)
        self.audit(changed)
        for stale in ["calendar-3", "calendar-4"]:
            changed["cases"][0]["model_identity"] = stale
            with self.subTest(scope="mixed provider observation", identity=stale):
                with self.assertRaises(ValueError):
                    self.audit(changed)
            rules_fixture = dict(self.fixture, mode="rules")
            rules_result = dict(
                self.result, mode="rules", provider="complete-rules", model_identity=stale
            )
            with self.subTest(scope="rules-only envelope", identity=stale):
                with self.assertRaises(ValueError):
                    evaluate(rules_result, rules_fixture, self.rows, "pinned")

    def test_nonfinite_negative_boolean_durations_and_wrong_status_fail(self):
        for seconds in [float("nan"), float("inf"), -1, True, "0.5"]:
            changed = copy.deepcopy(self.result)
            changed["cases"][0]["interpretation_seconds"] = seconds
            with self.subTest(seconds=seconds), self.assertRaises(ValueError):
                self.audit(changed)
        changed = copy.deepcopy(self.result)
        changed["cases"][0]["status"] = "passed"
        with self.assertRaises(ValueError):
            self.audit(changed)

    def test_rules_no_match_retains_requested_denominator(self):
        self.fixture["mode"] = "rules"
        self.result.update(
            mode="rules", provider="complete-rules", model_identity=RULES_MODEL_IDENTITY
        )
        self.result["cases"] = [
            dict(id=r["id"], status="no_match", interpretation_seconds=0) for r in self.rows
        ]
        result = self.audit()
        self.assertEqual(result["requested_cases"], len(self.rows))
        self.assertEqual(result["status_counts"]["no_match"], len(self.rows))
        self.assertEqual(result["exact_matches"], 0)


if __name__ == "__main__":
    unittest.main()
