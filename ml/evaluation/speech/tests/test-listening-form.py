"""Refreshing a form must keep its questions and references bound to the rendered corpus."""

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SOURCE = Path(__file__).parents[1] / "listening_form.py"
spec = importlib.util.spec_from_file_location("listening_form", SOURCE)
form = importlib.util.module_from_spec(spec)
spec.loader.exec_module(form)


class FormRefreshTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        source = root / "ml/evaluation/speech/listening_form.py"
        source.parent.mkdir(parents=True)
        source.write_bytes(SOURCE.read_bytes())
        location = patch.object(form, "__file__", str(source))
        location.start()
        self.addCleanup(location.stop)
        self.run = root / ".local/runs/listening"
        (self.run / "blind").mkdir(parents=True)
        self.prompts = {
            "samples": [
                {
                    "id": "date",
                    "category": "date",
                    "question": "Which day?",
                    "text": "Monday",
                    "expected": "Monday",
                }
            ]
        }
        prompt_bytes = json.dumps(self.prompts).encode()
        (self.run / "prompts.json").write_bytes(prompt_bytes)
        # Hash validation does not decode audio. No synthesis or playback is needed.
        (self.run / "blind/Stimme-01-date.wav").write_bytes(b"synthetic hash fixture")
        self.manifest = {
            "source_identities": {
                "ml/evaluation/speech/prompts.json": hashlib.sha256(prompt_bytes).hexdigest()
            },
            "key": {
                "Stimme-01": {
                    "manifest": {
                        "samples": [
                            {
                                "id": "date",
                                "spoken_text": "Monday",
                                "sha256": hashlib.sha256(b"synthetic hash fixture").hexdigest(),
                            }
                        ]
                    }
                }
            },
        }
        self.write_manifest()

    def write_manifest(self):
        (self.run / "manifest.json").write_text(json.dumps(self.manifest))

    def contents(self):
        return {p.relative_to(self.run): p.read_bytes() for p in self.run.rglob("*") if p.is_file()}

    def test_unchanged_prompt_copy_refreshes_only_the_form(self):
        before = self.contents()
        form.refresh(self.run)
        for path, content in before.items():
            self.assertEqual((self.run / path).read_bytes(), content)
        self.assertIn("Monday", (self.run / "listening.html").read_text())
        identity = json.loads((self.run / "form.json").read_text())
        self.assertEqual(
            identity["audio_manifest_sha256"],
            hashlib.sha256(before[Path("manifest.json")]).hexdigest(),
        )

    def test_changed_references_or_questions_leave_existing_evidence_untouched(self):
        form.refresh(self.run)
        original = self.prompts["samples"][0].copy()
        for field in ["text", "expected", "question"]:
            with self.subTest(field=field):
                self.prompts["samples"][0] = original | {field: "different reference"}
                (self.run / "prompts.json").write_text(json.dumps(self.prompts))
                before = self.contents()
                with self.assertRaisesRegex(ValueError, "prompts"):
                    form.refresh(self.run)
                self.assertEqual(self.contents(), before)

    def test_missing_prompt_identity_cannot_rewrite_an_existing_form(self):
        form.refresh(self.run)
        del self.manifest["source_identities"]
        self.write_manifest()
        before = self.contents()
        with self.assertRaisesRegex(ValueError, "prompts"):
            form.refresh(self.run)
        self.assertEqual(self.contents(), before)


if __name__ == "__main__":
    unittest.main()
