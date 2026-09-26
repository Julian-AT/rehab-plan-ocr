"""Incomplete evidence and worse token/reload outcomes cannot promote a candidate."""

import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from batchnorm_stage import LEVELS, VARIANTS, decision


class DecisionTests(unittest.TestCase):
    def setUp(self):
        self.runs = [
            {
                "role": role,
                "cases": [{"id": str(i), "width": 320 if i < 3 else 640} for i in range(6)],
            }
            for role in ["frozen", "full"]
        ]
        self.rows = [
            {
                "role": run["role"],
                **case,
                "original_control_reproduced": True,
                "variants": {
                    name + "-" + level: {
                        "allclose": True,
                        "same_tokens": True,
                        "reload_bitwise_equal": True,
                    }
                    for name in VARIANTS
                    for level in LEVELS
                },
            }
            for run in self.runs
            for case in run["cases"]
        ]

    def test_complete_evidence_prefers_fewer_changes_but_never_qualifies_deployment(self):
        result = decision(self.rows, self.runs)
        self.assertEqual(result["selected_for_full_corpus"], "division")
        self.assertTrue(result["controls_valid"])
        self.assertFalse(result["qualified"])

    def test_incomplete_duplicate_reordered_or_uncontrolled_cases_reject_all_variants(self):
        uncontrolled = copy.deepcopy(self.rows)
        uncontrolled[5]["original_control_reproduced"] = False
        for rows in [
            self.rows[:-1],
            self.rows + [self.rows[-1]],
            self.rows[1:] + self.rows[:1],
            uncontrolled,
        ]:
            result = decision(rows, self.runs)
            self.assertFalse(result["controls_valid"])
            self.assertIsNone(result["selected_for_full_corpus"])

    def test_each_level_requires_numeric_tokens_and_exact_reload(self):
        for key in ["allclose", "same_tokens", "reload_bitwise_equal"]:
            for level in LEVELS:
                rows = copy.deepcopy(self.rows)
                rows[0]["variants"]["division-" + level][key] = False
                result = decision(rows, self.runs)
                self.assertEqual(result["selected_for_full_corpus"], "division-convolution")
                rows[1]["variants"]["division-convolution-" + level][key] = False
                self.assertIsNone(decision(rows, self.runs)["selected_for_full_corpus"])

    def test_missing_candidate_or_evidence_does_not_pass(self):
        rows = copy.deepcopy(self.rows)
        del rows[3]["variants"]["division-ORT_ENABLE_ALL"]
        del rows[7]["variants"]["division-convolution-ORT_DISABLE_ALL"]["same_tokens"]
        self.assertIsNone(decision(rows, self.runs)["selected_for_full_corpus"])


if __name__ == "__main__":
    unittest.main()
