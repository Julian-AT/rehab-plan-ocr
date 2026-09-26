"""Data integrity checks use isolated temporary invented files only."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "dataset", Path(__file__).resolve().parents[4] / "ml/data/annotation/dataset.py"
)
dataset = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dataset)


class DatasetTests(unittest.TestCase):
    def test_new_inventory_cannot_replace_existing_reference_relationships(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            (source / "one.png").write_bytes(b"invented original")
            dataset.PRIVATE = root / "private"
            dataset.inventory(source)
            before = (dataset.PRIVATE / "inventory.json").read_bytes()
            with self.assertRaisesRegex(ValueError, "Existing inventory preserved"):
                dataset.inventory(source)
            self.assertEqual((dataset.PRIVATE / "inventory.json").read_bytes(), before)

    def test_legacy_relocate_copies_and_preserves_originals_inventory_and_receipt(self):
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
            inventory = dataset.PRIVATE / "inventory.json"
            before = inventory.read_bytes()
            dataset.relocate()
            receipt_path = dataset.PRIVATE / "copy-receipt.json"
            receipt_before = (receipt_path.read_bytes(), receipt_path.stat().st_mtime_ns)
            dataset.relocate()
            self.assertEqual((dataset.PRIVATE / "raw/original.JPG").read_bytes(), b"invented bytes")
            self.assertEqual(photo.read_bytes(), b"invented bytes")
            self.assertTrue(other.exists())
            self.assertEqual(inventory.read_bytes(), before)
            self.assertEqual(
                (receipt_path.read_bytes(), receipt_path.stat().st_mtime_ns), receipt_before
            )
            receipt = json.loads(receipt_before[0])
            self.assertEqual(receipt["status"], "copied_hashes_verified")
            self.assertEqual(receipt["source_deletions"], 0)

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

    def test_source_changed_after_preflight_is_preserved_and_not_certified(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            photo = source / "original.png"
            photo.write_bytes(b"initial")
            dataset.PRIVATE = root / "private"
            dataset.inventory(source)
            inventory = dataset.PRIVATE / "inventory.json"
            before = inventory.read_bytes()
            target = dataset.PRIVATE / "raw/original.png"
            target.parent.mkdir()
            target.write_bytes(b"initial")
            original_digest, checks = dataset.digest, 0

            def changing_digest(path):
                nonlocal checks
                result = original_digest(path)
                if path == target:
                    checks += 1
                    if checks == 2:
                        photo.write_bytes(b"concurrently changed original")
                return result

            with patch.object(dataset, "digest", side_effect=changing_digest):
                with self.assertRaisesRegex(ValueError, "changed original preserved"):
                    dataset.relocate()
            self.assertEqual(photo.read_bytes(), b"concurrently changed original")
            self.assertEqual(target.read_bytes(), b"initial")
            self.assertEqual(inventory.read_bytes(), before)
            self.assertFalse((dataset.PRIVATE / "copy-receipt.json").exists())

    def test_concurrent_destination_and_existing_partial_file_are_never_overwritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            photo = source / "original.png"
            photo.write_bytes(b"initial")
            dataset.PRIVATE = root / "private"
            dataset.inventory(source)
            target = dataset.PRIVATE / "raw/original.png"
            target.parent.mkdir()
            partial = target.with_suffix(".png.part")
            partial.write_bytes(b"existing interrupted copy")
            copy = dataset.shutil.copy2

            def competing_copy(source, destination):
                copy(source, destination)
                target.write_bytes(b"another writer's destination")

            with patch.object(dataset.shutil, "copy2", side_effect=competing_copy):
                with self.assertRaises(FileExistsError):
                    dataset.relocate()
            self.assertEqual(photo.read_bytes(), b"initial")
            self.assertEqual(target.read_bytes(), b"another writer's destination")
            self.assertEqual(partial.read_bytes(), b"existing interrupted copy")
            self.assertFalse((dataset.PRIVATE / "copy-receipt.json").exists())

    def test_differing_existing_receipt_is_preserved_before_copying(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            photo = source / "original.png"
            photo.write_bytes(b"initial")
            dataset.PRIVATE = root / "private"
            dataset.inventory(source)
            receipt = dataset.PRIVATE / "copy-receipt.json"
            receipt.write_text('{"historical": true}\n')
            with self.assertRaisesRegex(ValueError, "Existing copy receipt differs"):
                dataset.relocate()
            self.assertEqual(receipt.read_text(), '{"historical": true}\n')
            self.assertEqual(photo.read_bytes(), b"initial")
            self.assertFalse((dataset.PRIVATE / "raw").exists())

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
            with self.assertRaisesRegex(ValueError, "Legacy day-only"):
                dataset.freeze(grouping)
            self.assertFalse((dataset.PRIVATE / "split.json").exists())


if __name__ == "__main__":
    unittest.main()
