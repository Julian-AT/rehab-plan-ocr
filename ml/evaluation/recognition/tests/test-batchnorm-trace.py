import copy
import importlib.util
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import batchnorm_trace as trace


class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.previous = {
            "runs": [
                {
                    "role": role,
                    "cases": [{"id": str(i), "width": 320 if i < 3 else 640} for i in range(6)],
                }
                for role in ["frozen", "full"]
            ]
        }
        self.report = {
            "controls_valid": True,
            "sources_unchanged": True,
            "selected_for_full_corpus": None,
            "cases": [
                {
                    "role": run["role"],
                    **case,
                    "original_control_reproduced": True,
                    "variants": {
                        trace.VARIANT: {
                            "allclose": case["id"] != "3",
                            "same_tokens": True,
                            "reload_bitwise_equal": True,
                        }
                    },
                }
                for run in self.previous["runs"]
                for case in run["cases"]
            ],
        }

    def test_first_remaining_failure_is_fixed_before_tracing(self):
        before = copy.deepcopy((self.previous, self.report))
        entry, index, row = trace.select_case(self.previous, self.report)
        self.assertEqual((entry["role"], index, row["width"]), ("frozen", 3, 640))
        self.assertEqual(before, (self.previous, self.report))

    def test_reordered_missing_duplicate_or_successful_evidence_is_rejected(self):
        for mutation in ["reordered", "missing", "duplicate", "success"]:
            report = copy.deepcopy(self.report)
            if mutation == "reordered":
                report["cases"].reverse()
            elif mutation == "missing":
                report["cases"].pop()
            elif mutation == "duplicate":
                report["cases"][-1] = report["cases"][0]
            else:
                for row in report["cases"]:
                    row["variants"][trace.VARIANT]["allclose"] = True
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                trace.select_case(self.previous, report)

    def test_failed_late_reload_or_original_control_cannot_select_an_earlier_case(self):
        for field in ["original", "reload", "source"]:
            report = copy.deepcopy(self.report)
            if field == "original":
                report["cases"][-1]["original_control_reproduced"] = False
            elif field == "reload":
                report["cases"][-1]["variants"][trace.VARIANT]["reload_bitwise_equal"] = False
            else:
                report["sources_unchanged"] = False
            with self.subTest(field=field), self.assertRaises(ValueError):
                trace.select_case(self.previous, report)

    def test_unmapped_prior_outputs_or_perturbed_controls_prevent_earliest_claim(self):
        rows = [
            {"program_index": 2, "bitwise_equal": True, "allclose": True},
            {"program_index": 4, "bitwise_equal": False, "allclose": True},
        ]
        result = trace.trace_conclusion(rows, [{"program_index": 3}], True)
        self.assertFalse(result["earliest_operation_established"])
        self.assertEqual(result["first_mapped_difference"], rows[1])
        result = trace.trace_conclusion(rows, [], False)
        self.assertFalse(result["earliest_operation_established"])
        self.assertIsNone(result["first_mapped_difference"])
        self.assertTrue(
            trace.trace_conclusion(rows, [{"program_index": 9}], True)[
                "earliest_operation_established"
            ]
        )

    @unittest.skipUnless(importlib.util.find_spec("numpy"), "Requires pinned OCR environment")
    def test_byte_control_distinguishes_signed_zero_and_rejects_dtype_drift(self):
        import numpy as np

        expected = np.asarray([0.0, 1.0], dtype=np.float32)
        actual = np.asarray([-0.0, 1.0], dtype=np.float32)
        self.assertFalse(trace.measure(expected, actual)["bitwise_equal"])
        self.assertTrue(trace.measure(expected, actual)["allclose"])
        self.assertTrue(trace.measure(expected, expected.copy())["bitwise_equal"])
        with self.assertRaises(ValueError):
            trace.measure(expected, expected.astype(np.float64))


if __name__ == "__main__":
    unittest.main()
