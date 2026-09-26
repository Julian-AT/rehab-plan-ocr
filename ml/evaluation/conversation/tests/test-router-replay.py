"""Paired replay must retain unsafe regressions and reject incomplete evidence."""

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
from ml.evaluation.conversation.app_evaluation import prepare  # noqa: E402
from ml.evaluation.conversation.router_replay import VARIANTS, assess  # noqa: E402
from ml.training.assistant.prepare import examples  # noqa: E402


class ReplayTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        path = Path(self.temp.name) / "dataset.json"
        path.write_text(
            json.dumps(
                dict(
                    schema_version=1,
                    kind="invented-development-dialogues",
                    final_holdout=False,
                    samples=examples(0, 20260917),
                )
            )
        )
        self.fixture, self.rows = prepare(path, "paired", "custom")
        self.recorded = dict(variants=[dict(id=name, model_identity="pinned") for name in VARIANTS])
        self.result = dict(
            kind="paired-recorded-synthetic-response-replay",
            qualified=False,
            fresh_inference=False,
            full_voice_workflow=False,
            variants=[
                dict(
                    id=name,
                    recorded_responses_admitted=len(self.rows),
                    cases=[
                        dict(
                            id=r["id"],
                            family=r["family"],
                            expected=r["expected"],
                            operation=r["expected"],
                            provider="recorded-response",
                            recorded_response_admitted=True,
                        )
                        for r in self.rows
                    ],
                )
                for name in VARIANTS
            ],
        )

    def audit(self, result=None):
        return assess(result or self.result, self.fixture, self.rows, self.recorded)

    def test_regression_is_reported_separately_from_total_quality(self):
        changed = copy.deepcopy(self.result)
        case = changed["variants"][2]["cases"][0]
        case["operation"] = dict(action="remove", query=dict(reference="termin-1"))
        report = self.audit(changed)
        self.assertEqual(report["new_unsafe_proposed_mutations"], [case["id"]])
        self.assertEqual(report["new_incorrect_cases"], [case["id"]])
        self.assertFalse(report["qualified"])
        self.assertEqual(report["independent_real_dialogues"], 0)
        self.assertEqual(len(report["variants"]["corrected-cli"]["dependency_components"]), 1)

    def test_partial_reordered_and_wrong_scope_evidence_is_rejected(self):
        changes = [
            ("qualified", True),
            ("fresh_inference", True),
            ("full_voice_workflow", True),
            ("variants", self.result["variants"][:-1]),
            ("variants", list(reversed(self.result["variants"]))),
        ]
        for key, value in changes:
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.audit(dict(self.result, **{key: value}))
        changed = copy.deepcopy(self.result)
        changed["variants"][1]["cases"].reverse()
        with self.assertRaises(ValueError):
            self.audit(changed)

    def test_provider_admission_must_match_actual_trace_and_count(self):
        for key, value in [("recorded_response_admitted", False), ("provider", "complete-rules")]:
            changed = copy.deepcopy(self.result)
            changed["variants"][2]["cases"][0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.audit(changed)
        changed = copy.deepcopy(self.result)
        changed["variants"][2]["recorded_responses_admitted"] -= 1
        with self.assertRaises(ValueError):
            self.audit(changed)


if __name__ == "__main__":
    unittest.main()
