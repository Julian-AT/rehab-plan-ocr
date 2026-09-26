"""Data integrity checks use isolated temporary invented files only."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "dataset", Path(__file__).resolve().parents[1] / "scripts/dataset.py"
)
dataset = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dataset)


class DatasetTests(unittest.TestCase):
    def test_relocation_preserves_names_bytes_and_unrelated_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            photo = source / "original.JPG"
            photo.write_bytes(b"invented bytes")
            other = source / "notes.txt"
            other.write_text("keep")
            dataset.PRIVATE = root / "private"
            dataset.inventory(source)
            dataset.relocate()
            dataset.relocate()
            self.assertEqual(
                (dataset.PRIVATE / "raw/original.JPG").read_bytes(), b"invented bytes"
            )
            self.assertFalse(photo.exists())
            self.assertTrue(other.exists())

    def test_changed_source_stops_before_movement(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            photo = source / "one.png"
            photo.write_bytes(b"initial")
            dataset.PRIVATE = root / "private"
            dataset.inventory(source)
            photo.write_bytes(b"changed")
            with self.assertRaises(ValueError):
                dataset.relocate()
            self.assertTrue(photo.exists())

    def test_alternates_share_day_and_page_without_doubling_schedule(self):
        groups = {
            "day": {
                "captures": [
                    {"id": "first", "pages": {"1": "a", "2": "b"}},
                    {"id": "second", "pages": {"1": "c", "2": "b"}},
                ]
            }
        }
        result = dataset.normalize_groups(groups, {"a", "b", "c"})
        self.assertEqual(result["day"]["document_hashes"], ["a", "b", "c"])
        self.assertEqual(len(result["day"]["captures"][1]["pages"]), 2)
        groups["day"]["captures"][1]["pages"] = {"1": "c"}
        with self.assertRaises(ValueError):
            dataset.normalize_groups(groups, {"a", "b", "c"})

    def test_freeze_groups_twenty_days_and_cannot_reshuffle(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            dataset.PRIVATE = root / "private"
            dataset.PRIVATE.mkdir()
            groups = {
                f"day-{i}": {"captures": [{"id": "photo", "pages": {"1": str(i)}}]}
                for i in range(20)
            }
            grouping = root / "groups.json"
            grouping.write_text(json.dumps(groups))
            dataset.write(
                dataset.PRIVATE / "inventory.json",
                {"entries": [{"sha256": str(i)} for i in range(20)]},
            )
            dataset.freeze(grouping)
            days = json.loads((dataset.PRIVATE / "split.json").read_text())["days"]
            self.assertEqual(sum(d["split"] == "holdout" for d in days.values()), 4)
            self.assertEqual(
                [sum(d["fold"] == f for d in days.values()) for f in range(4)], [4] * 4
            )
            with self.assertRaises(ValueError):
                dataset.freeze(grouping)


if __name__ == "__main__":
    unittest.main()
