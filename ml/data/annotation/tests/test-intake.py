"""Consent scope, provenance and original preservation; invented byte fixtures only."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("intake", Path(__file__).parents[1] / "intake.py")
intake = importlib.util.module_from_spec(spec)
spec.loader.exec_module(intake)


class IntakeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "invented.png"
        self.source.write_bytes(b"invented original")
        evidence = self.root / "receipt.txt"
        evidence.write_text("invented receipt, not an actual consent")
        self.request = {
            "schema_version": 1,
            "consents": [
                {
                    "id": "c01",
                    "status": "active",
                    "reviewed": True,
                    "reviewer_id": "r01",
                    "reviewed_at": "2026-09-01T10:00:00+02:00",
                    "retain_until": "2099-01-01",
                    "purposes": ["schedule_evaluation"],
                    "evidence": "receipt.txt",
                    "evidence_sha256": intake.sha(evidence),
                }
            ],
            "entries": [
                {
                    "id": "e01",
                    "kind": "schedule",
                    "path": "invented.png",
                    "related_ids": ["series01", "page01", "day01"],
                    "consent_id": "c01",
                    "purposes": ["schedule_evaluation"],
                }
            ],
        }
        self.path = self.root / "request.json"
        self.output = self.root / "batch"

    def run_intake(self):
        self.path.write_text(json.dumps(self.request))
        return intake.prepare(self.path, self.output)

    def test_original_copy_and_receipt_separation_without_approval(self):
        report = self.run_intake()
        entry = report["entries"][0]
        self.assertEqual((self.output / entry["local_path"]).read_bytes(), self.source.read_bytes())
        self.assertFalse(report["approved"])
        self.assertFalse(report["groups_frozen"])
        self.assertEqual(report["partition"], "unassigned")
        self.assertNotIn("evidence", report["consents"][0])
        self.assertEqual(len(list((self.output / "raw").iterdir())), 1)
        before = (self.output / "manifest.json").read_bytes()
        with self.assertRaises(FileExistsError):
            self.run_intake()
        self.assertEqual((self.output / "manifest.json").read_bytes(), before)

    def test_unapproved_expired_withdrawn_or_changed_evidence_rejected_before_copy(self):
        original = self.request["consents"][0].copy()
        for changes in [
            {"reviewed": False},
            {"status": "withdrawn"},
            {"retain_until": "2000-01-01"},
            {"evidence_sha256": "0" * 64},
            {"reviewed_at": "2026-09-01T10:00:00"},
        ]:
            with self.subTest(changes=changes):
                self.request["consents"][0] = original | changes
                with self.assertRaises(ValueError):
                    self.run_intake()
                self.assertFalse(self.output.exists())
                self.assertTrue(self.source.exists())

    def test_evaluation_consent_does_not_allow_training(self):
        self.request["entries"][0]["purposes"] = ["ocr_training"]
        with self.assertRaisesRegex(ValueError, "outside"):
            self.run_intake()
        self.assertFalse(self.output.exists())

    def test_speech_requires_persistent_speaker_relationship(self):
        self.source.rename(self.root / "invented.wav")
        self.request["consents"][0]["purposes"] = ["speech_evaluation"]
        entry = self.request["entries"][0]
        entry.update(
            kind="speech", path="invented.wav", speaker_id="s01", purposes=["speech_evaluation"]
        )
        with self.assertRaisesRegex(ValueError, "speaker group"):
            self.run_intake()
        entry["related_ids"].append("speaker_s01")
        report = self.run_intake()
        self.assertIn("speaker_s01", report["entries"][0]["related_ids"])

    def test_duplicates_share_bytes_but_keep_capture_relationships(self):
        self.request["entries"].append(self.request["entries"][0] | {"id": "e02"})
        report = self.run_intake()
        self.assertEqual(len(report["entries"]), 2)
        self.assertEqual(len(list((self.output / "raw").iterdir())), 1)

    def test_interrupted_copy_is_incomplete_and_original_remains(self):
        with patch.object(intake.shutil, "copyfile", side_effect=OSError("disk full")):
            with self.assertRaises(OSError):
                self.run_intake()
        report = json.loads((self.output / "manifest.json").read_text())
        self.assertEqual(report["status"], "incomplete")
        self.assertFalse(report["approved"])
        self.assertEqual(self.source.read_bytes(), b"invented original")

    def test_symlink_input_and_duplicate_ids_are_rejected(self):
        link = self.root / "alias.png"
        link.symlink_to(self.source)
        self.request["entries"][0]["path"] = "alias.png"
        with self.assertRaises(ValueError):
            self.run_intake()
        self.request["entries"][0]["path"] = "invented.png"
        self.request["entries"].append(self.request["entries"][0].copy())
        with self.assertRaisesRegex(ValueError, "Duplicate entry"):
            self.run_intake()
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
