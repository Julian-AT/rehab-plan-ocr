"""Synthetic training must retain actual pixels, frozen groups and honest provenance."""

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import contract
import synthetic_data

FONT = next(
    p
    for p in [
        Path("/System/Library/Fonts/Supplemental/Arial.ttf"),
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
    ]
    if p.exists()
)


class SyntheticCoverageTests(unittest.TestCase):
    def test_nonempty_but_insufficient_field_coverage_is_rejected(self):
        rows = [
            {
                "partition": partition,
                "group": str(index),
                "field": field,
                "text": f"{partition}:{field}",
            }
            for partition in ["train", "validation"]
            for field in sorted(synthetic_data.REQUIRED_FIELDS)
            for index in range(2 if field != "start_time" or partition == "train" else 1)
        ]
        with self.assertRaisesRegex(
            ValueError, "validation coverage below minimum 2 for start_time"
        ):
            synthetic_data.coverage_report(rows, rows, {"train": 2, "validation": 2})

    def test_text_in_another_training_field_is_not_novel(self):
        rows = [
            {
                "partition": partition,
                "group": partition,
                "field": field,
                "text": f"{partition}:{field}",
            }
            for partition in ["train", "validation"]
            for field in sorted(synthetic_data.REQUIRED_FIELDS)
        ]
        report = synthetic_data.coverage_report(rows, rows)
        self.assertEqual(report["validation"]["fields"]["title"]["unseen_in_training_source"], 1)
        # An unselected note is still part of the training source and can leak a title.
        leaked = {
            "partition": "train",
            "group": "another-source",
            "field": "notes",
            "text": "validation:title",
        }
        with self.assertRaisesRegex(ValueError, "no unseen text for title"):
            synthetic_data.coverage_report([*rows, leaked], rows)


class SyntheticDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temp.cleanup)
        cls.root = Path(cls.temp.name)
        cls.source = cls.root / "source"
        synthetic_data.generator().generate(cls.source, FONT, count=20)
        cls.output = cls.root / "prepared"
        cls.dataset = synthetic_data.prepare(cls.output, cls.source, FONT, 28, 14, 20260918)
        cls.path = cls.output / "dataset.json"
        cls.dictionary = list(set("".join(r["text"] for r in cls.dataset["samples"])))

    def setUp(self):
        self.path.write_text(json.dumps(self.dataset))

    def test_repeated_preparation_and_full_validation_are_identical(self):
        repeated, _ = synthetic_data.build(self.source, FONT, 28, 14, 20260918)
        self.assertEqual(repeated, self.dataset)
        self.assertEqual(contract.validate_dataset(self.path, self.dictionary), self.dataset)
        self.assertEqual(len(self.dataset["samples"]), 42)
        self.assertFalse(self.dataset["qualified"])
        self.assertFalse(self.dataset["final_holdout"])
        self.assertGreater(self.dataset["input_counts"]["non_plan"], 0)
        self.assertGreater(self.dataset["input_counts"]["unusable"], 0)

    def test_groups_and_pixels_do_not_cross_partitions(self):
        partitions = {}
        for row in self.dataset["samples"]:
            self.assertEqual(row["partition"], self.dataset["source_groups"][row["group"]])
            for field in ["group", "source_sha256", "image_sha256"]:
                key = field, row[field]
                self.assertEqual(partitions.setdefault(key, row["partition"]), row["partition"])
        for partition in ["train", "validation"]:
            fields = {r["field"] for r in self.dataset["samples"] if r["partition"] == partition}
            self.assertEqual(fields, synthetic_data.REQUIRED_FIELDS)
            self.assertTrue(fields.issubset(contract.CRITICAL | {"notes"}))

    def test_novel_language_fields_survive_duplicate_exclusion_and_selection(self):
        validation = self.dataset["coverage"]["validation"]
        self.assertEqual(validation["samples"], 14)
        for field in ["title", "location", "notes"]:
            self.assertGreater(validation["fields"][field]["unseen_in_training_source"], 0)
            self.assertGreater(validation["fields"][field]["groups"], 0)
        with self.assertRaisesRegex(ValueError, "pre-rendering seed"):
            synthetic_data.build(self.source, FONT, 28, 14, 42)
        with self.assertRaisesRegex(ValueError, "coverage missing field"):
            synthetic_data.build(self.source, FONT, 28, 3, 20260918)

    def test_existing_v2_receipts_remain_replayable_without_rewriting(self):
        legacy = synthetic_data.legacy_adapter()
        self.assertEqual(
            contract.sha(Path(legacy.__file__)),
            "4188d66df8505826cb23cb4e2a91e35087c8690aa96b91bd0894f6560d1fca3a",
        )
        self.assertEqual(
            contract.sha(legacy.GENERATOR),
            "7fed31c8f10d7ce85fe5fb38e6d052c32f8af5991dd4ffc0ee8835457e6beb48",
        )
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "v2"
            legacy.generator().generate(source, FONT, count=20)
            original, _ = legacy.build(source, FONT, 28, 14, 20260918)
            self.assertGreater(original["excluded_validation_duplicate_crops"], 0)
            replayed, _ = synthetic_data.build(source, FONT, 28, 14, 20260918)
            self.assertEqual(original, replayed)
            synthetic_data.verify(original)

    def test_rehashed_false_labels_still_fail_pixel_verification(self):
        path = self.source / "plan-000.json"
        manifest_path = self.source / "manifest.json"
        original, original_manifest = path.read_bytes(), manifest_path.read_bytes()
        try:
            labels = json.loads(original)
            labels["lines"][0]["text"] = "Nicht wirklich gedruckt"
            path.write_text(json.dumps(labels))
            manifest = json.loads(original_manifest)
            manifest["records"][0]["labels_sha256"] = contract.sha(path)
            manifest_path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, "pixels differ"):
                synthetic_data.verify(self.dataset)
        finally:
            path.write_bytes(original)
            manifest_path.write_bytes(original_manifest)

    def test_changed_targets_groups_and_provenance_are_rejected(self):
        for change in [
            lambda d: d["samples"][0].update(text="Nicht gedruckt"),
            lambda d: d["samples"][0].update(partition="validation"),
            lambda d: d["samples"].pop(),
            lambda d: d["preparation"].update(adapter_sha256="0" * 64),
            lambda d: d["coverage"]["validation"]["fields"]["title"].update(
                unseen_in_training_source=999
            ),
        ]:
            changed = copy.deepcopy(self.dataset)
            change(changed)
            with self.assertRaisesRegex(ValueError, "changed"):
                synthetic_data.verify(changed)

    def test_source_changes_are_rejected_without_rewriting_receipts(self):
        source = self.source / "plan-000.json"
        original = source.read_bytes()
        try:
            source.write_bytes(original + b"\n")
            with self.assertRaisesRegex(ValueError, "labels changed"):
                synthetic_data.verify(self.dataset)
        finally:
            source.write_bytes(original)

    def test_prepared_pixels_and_reusing_output_are_rejected(self):
        path = self.output / self.dataset["samples"][0]["image"]
        original = path.read_bytes()
        try:
            Image.new("RGB", (30, 30), "white").save(path)
            with self.assertRaisesRegex(ValueError, "pixels changed"):
                contract.validate_dataset(self.path, self.dictionary)
        finally:
            path.write_bytes(original)
        with self.assertRaises(FileExistsError):
            synthetic_data.prepare(self.output, self.source, FONT, 28, 14, 20260918)


if __name__ == "__main__":
    unittest.main()
