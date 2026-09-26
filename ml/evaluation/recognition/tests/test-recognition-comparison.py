"""Acceptance gates must reject relocated errors and slow repeated processes."""

import importlib.util
import sys
import unittest
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4] / "ml/evaluation/recognition"))
spec = importlib.util.spec_from_file_location(
    "comparison",
    Path(__file__).resolve().parents[4] / "ml/evaluation/recognition/compare-recognition.py",
)
comparison = importlib.util.module_from_spec(spec)
spec.loader.exec_module(comparison)


def result(*, errors=(), corrections=2, elapsed=100, repeat=0):
    metrics = defaultdict(int)
    metrics.update(
        critical_errors=list(errors),
        critical_false_acceptances=[],
        field_corrections_needed=corrections,
        fully_correct_count=10 - corrections,
        printed_fields={},
        correct_printed_fields={},
        empty_fields={},
        correct_empty_fields={},
    )
    return dict(
        source_hash="invented-photo",
        repeat=repeat,
        metrics=metrics,
        wall_ms=elapsed,
        total_ms=elapsed,
    )


class ComparisonTests(unittest.TestCase):
    def test_relocated_critical_error_is_not_hidden_by_better_total(self):
        base = [result(errors=["row1:start", "row2:start"], corrections=3)]
        candidate = [result(errors=["row3:date"], corrections=1, elapsed=50)]
        comparison_result = comparison.compare(base, candidate)
        self.assertTrue(comparison_result["desktop_quality_improved"])
        self.assertEqual(comparison_result["new_critical_errors"], ["invented-photo:row3:date"])
        self.assertFalse(comparison_result["eligible_for_iphone_comparison"])

    def test_later_processes_affect_latency_and_error_gates(self):
        base = [result(repeat=i) for i in range(5)]
        candidate = [result(corrections=1, elapsed=50, repeat=i) for i in range(5)]
        self.assertTrue(comparison.compare(base, candidate)["eligible_for_iphone_comparison"])
        self.assertFalse(comparison.compare(base, candidate)["eligible_as_default"])
        candidate[-1]["wall_ms"] = 200
        self.assertFalse(comparison.compare(base, candidate)["desktop_timing_not_slower"])
        candidate[-1]["wall_ms"] = 50
        candidate[-1]["metrics"]["critical_false_acceptances"] = ["row4:end"]
        self.assertFalse(comparison.compare(base, candidate)["eligible_for_iphone_comparison"])

    def test_tail_percentile_uses_nearest_rank(self):
        self.assertEqual(comparison.timing(range(1, 21))["p95_ms"], 19)
        self.assertEqual(comparison.timing([1, 2, 3, 4, 9])["p95_ms"], 9)

    def test_fewer_bad_fields_without_more_correct_events_is_not_a_win(self):
        base = [result(corrections=3)]
        candidate = [result(corrections=2, elapsed=50)]
        candidate[0]["metrics"]["fully_correct_count"] = base[0]["metrics"]["fully_correct_count"]
        self.assertFalse(comparison.compare(base, candidate)["desktop_quality_improved"])

    def test_incomplete_duplicate_or_mismatched_measurements_fail_closed(self):
        for base, candidate in [
            ([], []),
            ([result()], []),
            ([result(), result()], [result()]),
            ([result()], [result(), result()]),
            ([result(repeat=1)], [result(repeat=1)]),
            ([result(), result(repeat=2)], [result(), result(repeat=2)]),
            ([result()], [dict(result(), source_hash="different-photo")]),
            ([result()], [result(elapsed=float("nan"))]),
            ([result()], [result(elapsed=float("inf"))]),
            ([result()], [result(elapsed=-1)]),
        ]:
            with self.subTest(base=base, candidate=candidate), self.assertRaises(ValueError):
                comparison.compare(base, candidate)

    def test_each_photo_requires_all_repeats(self):
        partial = [result(), result(repeat=1), dict(result(), source_hash="another-photo")]
        with self.assertRaises(ValueError):
            comparison.compare(partial, partial)

    def test_later_quality_regression_cannot_hide_behind_first_repeat(self):
        base = [result(repeat=i) for i in range(2)]
        candidate = [result(corrections=1, elapsed=50, repeat=i) for i in range(2)]
        candidate[1]["metrics"]["field_corrections_needed"] = 9
        candidate[1]["metrics"]["fully_correct_count"] = 1
        checked = comparison.compare(base, candidate)
        self.assertTrue(checked["quality_by_repeat"][0]["improved"])
        self.assertFalse(checked["quality_by_repeat"][1]["improved"])
        self.assertFalse(checked["eligible_for_iphone_comparison"])

    def test_new_missing_rows_are_reported_and_block_promotion(self):
        base, candidate = [result()], [result(corrections=1, elapsed=50)]
        candidate[0]["metrics"]["missed_count"] = 1
        checked = comparison.compare(base, candidate)
        self.assertEqual(checked["photos_with_additional_missed_rows"], ["invented-photo"])
        self.assertFalse(checked["eligible_for_iphone_comparison"])

    def test_changed_reference_count_blocks_comparison(self):
        base, candidate = [result()], [result(corrections=1, elapsed=50)]
        candidate[0]["metrics"]["reference_count"] = 11
        with self.assertRaises(ValueError):
            comparison.compare(base, candidate)


if __name__ == "__main__":
    unittest.main()
