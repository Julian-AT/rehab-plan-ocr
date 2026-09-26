"""Known-failure expansion preserves its controls and cannot grant model qualification."""

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from ml.training.assistant import contract, development_data, prepare  # noqa: E402


class DevelopmentDataTests(unittest.TestCase):
    def test_original_validation_and_group_assignments_are_unchanged(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            original = {
                "schema_version": 1,
                "kind": "invented-development-dialogues",
                "final_holdout": False,
                "seed": 20260917,
                "samples": [row for i in range(4) for row in prepare.examples(i, 20260917)],
            }
            source = root / "original.json"
            contract.write(source, original)
            before = source.read_bytes()
            result = development_data.prepare(source, root / "expanded")
            contract.validate_dataset(root / "expanded/dataset.json")
            self.assertEqual(source.read_bytes(), before)
            self.assertEqual(result["samples"][:152], original["samples"])
            self.assertEqual(
                [r for r in result["samples"] if r["partition"] == "validation"],
                [r for r in original["samples"] if r["partition"] == "validation"],
            )
            self.assertEqual(len(result["samples"]), 312)
            self.assertEqual(result["source_dataset_sha256"], contract.sha(source))
            self.assertEqual(result["validation_use"], "previously-examined-development-only")
            self.assertEqual(result["independent_real_dialogues"], 0)
            self.assertIs(result["qualified"], False)
            self.assertTrue(all(r["human_review"] == "pending" for r in result["samples"]))
            with self.assertRaises(FileExistsError):
                development_data.prepare(source, root / "expanded")
            with self.assertRaisesRegex(ValueError, "once"):
                development_data.prepare(root / "expanded/dataset.json", root / "twice")

    def test_dates_leap_boundary_and_minimal_changes(self):
        rows = {r["family"]: r for r in development_data.additional_examples(0, 59)}
        self.assertEqual(rows["v2-create-dotted-date"]["context"]["today"], "2028-02-29")
        self.assertEqual(
            rows["v2-create-dotted-date"]["expected"],
            {
                "action": "create",
                "change": {
                    "title": "Wassergymnastik",
                    "date": "2028-03-02",
                    "time": "07:00",
                },
            },
        )
        self.assertEqual(rows["v2-list-corrected-day"]["expected"]["query"]["date"], "2028-03-02")
        self.assertEqual(
            rows["v2-create-relative-minimal"]["expected"]["change"]["date"], "2028-03-01"
        )
        for family, field in [
            ("rename-not-remove", "title"),
            ("duration-not-remove", "duration"),
            ("time-only-explicit", "time"),
            ("date-only-explicit", "date"),
        ]:
            self.assertEqual(set(rows[f"v2-{family}"]["expected"]["change"]), {field})

    def test_questions_negations_and_constraints_remain_distinct(self):
        for index in range(16):
            rows = {r["family"]: r for r in development_data.additional_examples(index, 20260921)}
            for family in ["room-short", "room-no-change"]:
                answer = rows[f"v2-{family}"]["expected"]
                self.assertEqual(answer["action"], "calendar")
                self.assertEqual(answer["query"]["detail"], "room")
            bounds = rows["v2-bounded-window"]["expected"]["query"]
            self.assertLess(bounds["after"], bounds["before"])
            self.assertEqual(bounds["before"], "18:00")
            self.assertEqual(rows["v2-cancel-keep-values"]["expected"], {"action": "cancel"})
            for family in ["invalid-short-month", "invalid-iso-date"]:
                self.assertEqual(
                    rows[f"v2-{family}"]["expected"],
                    {
                        "action": "clarify",
                        "problem": "invalid_date",
                    },
                )

    def test_reviewed_or_holdout_sources_cannot_be_relabelled_as_synthetic(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            base = {
                "schema_version": 1,
                "kind": "invented-development-dialogues",
                "final_holdout": False,
                "samples": prepare.examples(0, 20260917),
            }
            for key, value in [("final_holdout", True), ("kind", "reviewed-development-dialogues")]:
                data = copy.deepcopy(base)
                data[key] = value
                path = root / "source.json"
                path.write_text(json.dumps(data))
                with self.assertRaises(ValueError):
                    development_data.prepare(path, root / key)
                self.assertFalse((root / key).exists())


if __name__ == "__main__":
    unittest.main()
