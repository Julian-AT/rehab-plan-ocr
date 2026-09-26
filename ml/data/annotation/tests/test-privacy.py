"""End-to-end privacy export checks use invented images and receipts only."""

import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from PIL import Image, ImageDraw

spec = importlib.util.spec_from_file_location(
    "privacy_fixtures", Path(__file__).with_name("test-reference-data.py")
)
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
refs = fixture.refs


class PrivacyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "raw").mkdir()
        self.references, inventory = [], []
        for i in range(4):
            ref = fixture.reference(i)
            path = self.root / "raw" / f"invented-{i}.png"
            image = Image.new("RGB", (100, 100), "white")
            draw = ImageDraw.Draw(image)
            draw.rectangle((15, 2, 45, 8), fill="black")  # Patient header outside the table.
            draw.rectangle((20, 25, 50, 35), fill="black")  # Identity within the table.
            draw.rectangle((70, 70, 75, 75), fill=(10 + i, 10, 10))
            image.save(path)
            sha = refs.file_hash(path)
            ref["document_hashes"] = [sha]
            ref["sources"][0].update(source_hash=sha, original_hash=sha)
            for line in ref["lines"]:
                line["source_hash"] = sha
            if i == 0:
                ref["appointments"][0]["title"] = "INVENTED PRIVATE IDENTITY"
                ref["appointments"][0]["fields"]["title"]["confirmed_value"] = (
                    "INVENTED PRIVATE IDENTITY"
                )
                ref["lines"][0]["text"] = "INVENTED PRIVATE IDENTITY"
                ref["lines"][0]["error_causes"] = ["INVENTED PRIVATE REVIEW NOTE"]
            self.references.append(ref)
            inventory.append({"filename": path.name, "sha256": sha})
        split = refs.grouping(self.references)
        for ref in self.references:
            source = ref["document_hashes"][0]
            ref["day_id"] = next(
                k for k, v in split["days"].items() if source in v["document_hashes"]
            )
            ref["approval_hash"] = refs.reference_hash(ref)
            refs.write(self.root / "labels/provisional" / f"{source}.json", ref)
        refs.write(self.root / "inventory.json", {"entries": inventory})
        refs.write(self.root / "split.json", split)
        refs.write(
            self.root / "crop-review.json",
            {
                "schema_version": 1,
                "reviewed_at": "2000-01-01T00:00:00+00:00",
                "lines": {
                    line["id"]: refs.crop_hash(line)
                    for ref in self.references
                    for line in ref["lines"]
                },
            },
        )
        self.source = self.references[0]["sources"][0]["source_hash"]
        self.reviews = fixture.approve_privacy(
            self.root,
            self.references,
            {
                self.source: [{"reason": "patient_identity", "rect": [15, 20, 60, 40]}],
            },
        )
        self.before = {path.name: refs.file_hash(path) for path in (self.root / "raw").iterdir()}
        self.original_recipes = refs.RECIPES
        refs.RECIPES = [("original", {}), ("quarter-90", {"turn": 1})]
        self.addCleanup(setattr, refs, "RECIPES", self.original_recipes)

    def update_receipt(self, change):
        path = self.root / "invented-intake.json"
        receipt = json.loads(path.read_text())
        change(receipt)
        refs.write(path, receipt)
        for review in self.reviews["sources"].values():
            review["authorization"]["intake_sha256"] = refs.file_hash(path)
            review["approval_hash"] = refs.privacy.approval_hash(review)
        refs.write(self.root / "privacy-review.json", self.reviews)

    def test_masks_remove_private_pixels_and_all_field_targets_but_preserve_originals(self):
        before_references = copy.deepcopy(self.references)
        output = self.root / "export"
        refs.export(self.root, output, 0, 1)
        for path in output.glob("*.jsonl"):
            self.assertNotIn("INVENTED PRIVATE IDENTITY", path.read_text())
        manifest = json.loads((output / "manifest.json").read_text())
        self.assertEqual(
            manifest["privacy_review"], refs.validate_privacy(self.root, self.references)
        )
        record = next(
            row
            for row in manifest["records"]
            if row["source_hash"] == self.source and row["name"] == "original"
        )
        path = refs.materialize(self.root, record["id"], 1)
        with Image.open(path) as image:
            self.assertGreater(min(image.getpixel((30, 30))), 245)
            self.assertGreater(min(image.getpixel((30, 5))), 245)
            self.assertLess(max(image.getpixel((72, 72))), 50)
        metadata = json.loads(path.with_suffix(".json").read_text())
        self.assertTrue(all(line["text"] == "" for line in metadata["lines"]))
        self.assertNotIn("INVENTED PRIVATE IDENTITY", path.with_suffix(".json").read_text())
        self.assertNotIn("INVENTED PRIVATE REVIEW NOTE", path.with_suffix(".json").read_text())
        with self.assertRaisesRegex(ValueError, "Unreadable"):
            refs.materialize_line(self.root, record["id"], self.references[0]["lines"][0]["id"], 1)
        self.assertEqual(before_references, self.references)
        self.assertEqual(
            self.before, {p.name: refs.file_hash(p) for p in (self.root / "raw").iterdir()}
        )

    def test_field_and_crop_approval_do_not_implicitly_approve_privacy(self):
        (self.root / "privacy-review.json").unlink()
        with self.assertRaisesRegex(ValueError, "Separate privacy"):
            refs.export(self.root, self.root / "denied", 0, 1)
        self.assertFalse((self.root / "denied").exists())

    def test_changed_masks_require_new_review_and_invalidate_old_materialization(self):
        refs.export(self.root, self.root / "export", 0, 1)
        manifest = json.loads((self.root / "export/manifest.json").read_text())
        identifier = manifest["records"][0]["id"]
        review = self.reviews["sources"][self.source]
        review["redactions"][0]["rect"][0] = 10
        refs.write(self.root / "privacy-review.json", self.reviews)
        with self.assertRaisesRegex(ValueError, "changed after approval"):
            refs.validate_privacy(self.root, self.references)
        review["approval_hash"] = refs.privacy.approval_hash(review)
        refs.write(self.root / "privacy-review.json", self.reviews)
        with self.assertRaisesRegex(ValueError, "Privacy review changed"):
            refs.materialize(self.root, identifier, 1)

    def test_withdrawn_expired_or_evaluation_only_consent_blocks_export(self):
        for changes in [
            {"status": "withdrawn"},
            {"retain_until": "2000-01-01"},
            {"purposes": ["schedule_evaluation"]},
        ]:
            with self.subTest(changes=changes):
                self.update_receipt(
                    lambda value: value["consents"][0].update(
                        {
                            "status": "active",
                            "retain_until": "2099-01-01",
                            "purposes": ["ocr_training"],
                        }
                        | changes
                    )
                )
                with self.assertRaisesRegex(ValueError, "consent"):
                    refs.export(self.root, self.root / "denied", 0, 1)
                self.assertFalse((self.root / "denied").exists())

    def test_intake_relationships_cannot_cross_frozen_groups(self):
        def join(value):
            for entry in value["entries"]:
                entry["related_ids"].append("same_revision_family")

        self.update_receipt(join)
        with self.assertRaisesRegex(ValueError, "one frozen source group"):
            refs.export(self.root, self.root / "denied", 0, 1)

    def test_same_crop_identifier_cannot_transfer_review_between_originals(self):
        first, second = self.references[:2]
        second["lines"][0]["id"] = first["lines"][0]["id"]
        with self.assertRaisesRegex(ValueError, "unique across"):
            refs.reviewed_crops(self.root, self.references)

    def test_masked_content_cannot_affect_any_of_the_forty_augmentation_recipes(self):
        ref = self.references[0]
        review = self.reviews["sources"][self.source]
        with Image.open(self.root / "raw/invented-0.png") as original:
            altered = original.copy()
            draw = ImageDraw.Draw(altered)
            draw.rectangle((15, 2, 45, 8), fill="red")
            draw.rectangle((20, 25, 50, 35), fill="blue")
            for name, recipe in self.original_recipes:
                with self.subTest(recipe=name):
                    first, labels, _ = refs.variant(
                        refs.privacy.mask_image(original, ref, review),
                        refs.privacy.sanitized(ref, review),
                        recipe,
                    )
                    other, again, _ = refs.variant(
                        refs.privacy.mask_image(altered, ref, review),
                        refs.privacy.sanitized(ref, review),
                        recipe,
                    )
                    self.assertEqual(first.tobytes(), other.tobytes())
                    self.assertEqual(labels, again)

    def test_privacy_draft_and_confirmation_never_invent_an_attestation(self):
        value = refs.privacy.draft(self.references, refs.reference_hash)
        self.assertFalse(value["sources"][self.source]["table_privacy_reviewed"])
        refs.write(self.root / "privacy-review.json", value)
        before = (self.root / "privacy-review.json").read_bytes()
        with self.assertRaisesRegex(ValueError, "draft first"):
            refs.privacy.confirm(
                self.root, self.references[0], "invented_operator", refs.reference_hash
            )
        self.assertEqual(before, (self.root / "privacy-review.json").read_bytes())

    def test_cli_draft_preserves_existing_review_and_explicit_confirmation_checks_receipt(self):
        path = self.root / "privacy-review.json"
        path.unlink()
        refs.execute(SimpleNamespace(command="privacy-draft", root=self.root))
        draft = path.read_bytes()
        with self.assertRaisesRegex(ValueError, "Existing privacy review"):
            refs.execute(SimpleNamespace(command="privacy-draft", root=self.root))
        self.assertEqual(draft, path.read_bytes())
        args = SimpleNamespace(
            command="privacy-approve",
            root=self.root,
            source_hash=self.source,
            reviewer="invented_operator",
        )
        with self.assertRaisesRegex(ValueError, "draft first"):
            refs.execute(args)
        refs.write(path, self.reviews)
        refs.execute(args)
        self.assertEqual(
            refs.validate_privacy(self.root, self.references)["review_file_sha256"],
            refs.file_hash(path),
        )
        before = path.read_bytes()
        args.reviewer = "not an opaque identifier"
        with self.assertRaises(ValueError):
            refs.execute(args)
        self.assertEqual(before, path.read_bytes())

    def test_wrong_original_missing_entry_purpose_and_invalid_masks_fail_closed(self):
        original = json.loads((self.root / "invented-intake.json").read_text())
        for changes in [{"source_sha256": "0" * 64}, {"purposes": ["schedule_evaluation"]}]:
            with self.subTest(changes=changes):

                def change(value):
                    value["entries"][0] = original["entries"][0] | changes

                self.update_receipt(change)
                with self.assertRaisesRegex(ValueError, "Original, source relationships"):
                    refs.export(self.root, self.root / "denied", 0, 1)
                self.assertFalse((self.root / "denied").exists())
        self.update_receipt(lambda value: value.update(original))
        review = self.reviews["sources"][self.source]
        for rect in [
            [-1, 20, 60, 40],
            [20, 20, 10, 40],
            [True, 20, 60, 40],
            [0, 0, float("nan"), 40],
        ]:
            with self.subTest(rect=rect):
                review["redactions"][0]["rect"] = rect
                review["approval_hash"] = refs.privacy.approval_hash(review)
                refs.write(self.root / "privacy-review.json", self.reviews)
                with self.assertRaisesRegex(ValueError, "finite original-pixel"):
                    refs.export(self.root, self.root / "denied", 0, 1)
                self.assertFalse((self.root / "denied").exists())


if __name__ == "__main__":
    unittest.main()
