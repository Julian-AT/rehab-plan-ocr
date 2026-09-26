"""Exercise export/materialization/revocation with isolated invented reference records."""

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import contract
import prepare
import train

ROOT = Path(__file__).resolve().parents[4]

# Reuse the established invented annotation fixture. Never open private references.
spec = importlib.util.spec_from_file_location(
    "reference_fixtures", ROOT / "ml/data/annotation/tests/test-reference-data.py"
)
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


class PreparedReferenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "references"
        self.root.mkdir()
        (self.root / "raw").mkdir()
        self.output = Path(self.temp.name) / "prepared"
        self.refs = prepare.reference_module()
        self.refs.RECIPES = [("original", {}), ("blur-light", {"blur": 0.6})]
        self.data, entries = [], []
        for i in range(4):
            ref = fixture.reference(i)
            image = self.root / "raw" / f"invented-{i}.png"
            Image.new("RGB", (100, 100), (40 + i * 40, 50, 90)).save(image)
            digest = contract.sha(image)
            ref["document_hashes"] = [digest]
            ref["sources"][0].update(source_hash=digest, original_hash=digest)
            for line in ref["lines"]:
                line["source_hash"] = digest
            self.data.append(ref)
            entries.append({"sha256": digest, "filename": image.name})
        split = self.refs.grouping(self.data)
        for ref in self.data:
            ref["day_id"] = next(
                k
                for k, v in split["days"].items()
                if ref["document_hashes"][0] in v["document_hashes"]
            )
            ref["approval_hash"] = self.refs.reference_hash(ref)
            self.refs.write(
                self.root / "labels/provisional" / (ref["document_hashes"][0] + ".json"), ref
            )
        self.refs.write(self.root / "inventory.json", {"entries": entries})
        self.refs.write(self.root / "split.json", split)
        self.refs.write(
            self.root / "crop-review.json",
            {
                "schema_version": 1,
                "reviewed_at": "2030-01-01",
                "lines": {
                    line["id"]: self.refs.crop_hash(line)
                    for ref in self.data
                    for line in ref["lines"]
                },
            },
        )
        self.patcher = patch.object(prepare, "reference_module", return_value=self.refs)
        fixture.approve_privacy(self.root, self.data)
        self.patcher.start()
        self.addCleanup(self.patcher.stop)

    def prepare(self):
        dataset = prepare.prepare_references(self.output, self.root, 0)
        path = self.output / "dataset.json"
        contract.write(path, dataset)
        dictionary = set("".join(r["text"] for r in dataset["samples"]))
        contract.validate_dataset(path, dictionary)
        train.current_review(dataset, path)
        return dataset, path

    def test_complete_adapter_preserves_time_fields_partitions_and_originals(self):
        before = {p.name: contract.sha(p) for p in (self.root / "raw").iterdir()}
        dataset, _ = self.prepare()
        self.assertEqual({r["partition"] for r in dataset["samples"]}, {"train", "validation"})
        self.assertEqual({r["variant"] for r in dataset["samples"]}, {"original", "blur-light"})
        fields = {r["field"] for r in dataset["samples"]}
        self.assertIn("start_time", fields)
        self.assertIn("end_time", fields)
        self.assertNotIn("start", fields)
        self.assertEqual(before, {p.name: contract.sha(p) for p in (self.root / "raw").iterdir()})

    def test_label_edit_or_removed_validation_sample_cannot_reuse_approval(self):
        dataset, path = self.prepare()
        row = dataset["samples"][0]
        previous = row["text"]
        row["text"] = "invented alteration"
        with self.assertRaisesRegex(ValueError, "label or partition"):
            train.current_review(dataset, path)
        row["text"] = previous
        dataset["samples"].pop()
        with self.assertRaisesRegex(ValueError, "complete approved export"):
            train.current_review(dataset, path)

    def test_revoked_crop_review_blocks_reuse(self):
        dataset, path = self.prepare()
        self.refs.write(
            self.root / "crop-review.json",
            {"schema_version": 1, "reviewed_at": "2030-01-01", "lines": {}},
        )
        with self.assertRaisesRegex(ValueError, "Crop review changed"):
            train.current_review(dataset, path)

    def test_changed_masks_and_sample_privacy_hash_block_prepared_reuse(self):
        dataset, path = self.prepare()
        original = dataset["samples"][0]["privacy_review_sha256"]
        dataset["samples"][0]["privacy_review_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "Privacy or purpose review changed"):
            train.current_review(dataset, path)
        dataset["samples"][0]["privacy_review_sha256"] = original
        source = self.data[0]["sources"][0]["source_hash"]
        fixture.approve_privacy(
            self.root,
            self.data,
            {source: [{"rect": [85, 85, 95, 95], "reason": "patient_identity"}]},
        )
        with self.assertRaisesRegex(ValueError, "Privacy or purpose review changed"):
            train.current_review(dataset, path)

    def test_revoked_or_expired_consent_and_removed_purpose_block_training(self):
        dataset, path = self.prepare()
        intake_path = self.root / "invented-intake.json"
        original = json.loads(intake_path.read_text())
        for alteration in [{"status": "revoked"}, {"retain_until": "2000-01-01"}, {"purposes": []}]:
            intake = json.loads(json.dumps(original))
            intake["consents"][0].update(alteration)
            self.refs.write(intake_path, intake)
            review = json.loads((self.root / "privacy-review.json").read_text())
            for source in review["sources"].values():
                source["authorization"]["intake_sha256"] = contract.sha(intake_path)
                source["approval_hash"] = self.refs.privacy.approval_hash(source)
            self.refs.write(self.root / "privacy-review.json", review)
            with self.subTest(alteration=alteration), self.assertRaisesRegex(ValueError, "consent"):
                train.current_review(dataset, path)

    def test_privacy_change_during_materialization_cannot_enter_dataset(self):
        materialize = self.refs.materialize_line

        def changed(*args):
            path = materialize(*args)
            metadata = json.loads(path.with_suffix(".json").read_text())
            metadata["privacy_review_sha256"] = "0" * 64
            self.refs.write(path.with_suffix(".json"), metadata)
            return path

        with patch.object(self.refs, "materialize_line", side_effect=changed):
            with self.assertRaisesRegex(ValueError, "changed during materialization"):
                prepare.prepare_references(self.output, self.root, 0)


if __name__ == "__main__":
    unittest.main()
