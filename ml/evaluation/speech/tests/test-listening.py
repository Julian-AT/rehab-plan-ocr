"""Incomplete, silent or substituted samples cannot enter a listening comparison."""

import importlib.util
import json
import tempfile
import unittest
import wave
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "listening", Path(__file__).parents[1] / "listening.py"
)
listening = importlib.util.module_from_spec(spec)
spec.loader.exec_module(listening)


class ListeningTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.audio(self.root / "date.wav")
        self.record = {"id": "date", "path": "date.wav", "spoken_text": "Am Montag."}

    def audio(self, path, content=b"\x10\x00\x20\x00"):
        with wave.open(str(path), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(24000)
            output.writeframes(content)

    def check(self, records):
        (self.root / "manifest.json").write_text(json.dumps({"samples": records}))
        return listening.checked_samples(self.root, {"date": "Am Montag."})

    def test_requires_every_case_once_and_identical_spoken_text(self):
        self.assertEqual(self.check([self.record])["samples"][0]["frames"], 2)
        for records in [
            [],
            [self.record, self.record],
            [{**self.record, "spoken_text": "Am Dienstag."}],
            [{**self.record, "sha256": "0" * 64}],
        ]:
            with self.assertRaises(ValueError):
                self.check(records)

    def test_silent_and_truncated_audio_are_rejected(self):
        self.audio(self.root / "date.wav", b"\x00" * 100)
        with self.assertRaises(ValueError):
            self.check([self.record])
        self.audio(self.root / "date.wav")
        path = self.root / "date.wav"
        path.write_bytes(path.read_bytes()[:-2])
        with self.assertRaises(ValueError):
            self.check([self.record])

    def test_audio_cannot_escape_the_export_directory(self):
        folder = self.root / "nested"
        folder.mkdir()
        (folder / "manifest.json").write_text(
            json.dumps({"samples": [{**self.record, "path": "../date.wav"}]})
        )
        with self.assertRaises(ValueError):
            listening.checked_samples(folder, {"date": "Am Montag."})

    def test_page_does_not_inject_reference_text_as_markup(self):
        listening.listening_page(
            self.root,
            ["Stimme-01"],
            [
                {
                    "id": "date",
                    "category": "Datum",
                    "question": "Welches Datum?",
                    "text": "<script>untrusted()</script>",
                    "expected": "Montag",
                }
            ],
            "a" * 64,
        )
        page = (self.root / "listening.html").read_text()
        self.assertIn("&lt;script&gt;untrusted()&lt;/script&gt;", page)
        self.assertNotIn("<script>untrusted()", page)
        self.assertIn("human_review_complete:false", page)


if __name__ == "__main__":
    unittest.main()
