"""A successful launch or old result must not qualify an app provider run."""

import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
from ml.evaluation.conversation.app_trial import compare, completed  # noqa: E402


class AppTrialTests(unittest.TestCase):
    def setUp(self):
        self.result = {
            "run_id": "current",
            "stage": "passed",
            "qualified": False,
            "calendar_operations": 0,
            "rules_passed": True,
            "model_identity": "pinned",
            "cases": [
                {
                    "id": "custom-date-0000",
                    "action": "calendar",
                    "detail": "next",
                    "date": "2031-05-16",
                },
                {
                    "id": "custom-room-0000",
                    "action": "update",
                    "reference": "termin-1",
                    "change_date": "2031-05-15",
                },
            ],
        }

    def test_stale_partial_wrong_model_and_mutated_runs_do_not_complete(self):
        self.assertTrue(completed(self.result, "current", "pinned"))
        for key, value in [
            ("run_id", "old"),
            ("stage", "started"),
            ("qualified", True),
            ("calendar_operations", 1),
            ("calendar_operations", False),
            ("rules_passed", False),
            ("model_identity", "other"),
            ("cases", []),
            ("cases", [None]),
        ]:
            with self.subTest(key=key, value=value):
                changed = copy.deepcopy(self.result)
                changed[key] = value
                self.assertFalse(completed(changed, "current", "pinned"))

    def test_compatibility_is_not_task_quality(self):
        cases = compare(self.result)
        self.assertEqual(sum(c["exact_match"] for c in cases), 0)
        self.assertEqual(sum(c["unsafe_proposed_mutation"] for c in cases), 1)
        self.assertFalse(self.result["qualified"])


if __name__ == "__main__":
    unittest.main()
