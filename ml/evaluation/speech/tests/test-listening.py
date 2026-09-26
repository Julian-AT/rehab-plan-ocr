"""Incomplete, silent or substituted samples cannot enter a listening comparison."""

import importlib.util
import json
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import wave
from pathlib import Path
from unittest.mock import patch

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

    def system_manifest(self):
        return {
            "schema_version": 2,
            "route": "host-product-system-speech-renderer",
            "renderer": "SystemSpeechRenderer",
            "shared_product_renderer": True,
            "rate_multiplier": 0.95,
            "status": "complete",
            "failed_samples": 0,
            "expected_samples": 1,
            "samples": [
                self.record
                | {
                    "status": "complete",
                    "frames": 2,
                    "sample_rate": 24_000,
                    "channels": 1,
                    "duration_seconds": 2 / 24_000,
                    "marks": [
                        {"text": "Am", "start": 0, "end": 1 / 24_000},
                        {"text": "Montag.", "start": 1 / 24_000, "end": 2 / 24_000},
                    ],
                }
            ],
        }

    def check_system(self, manifest):
        (self.root / "manifest.json").write_text(json.dumps(manifest))
        return listening.checked_samples(self.root, {"date": "Am Montag."}, system=True)

    def test_system_renderer_contract_requires_same_rate_complete_pcm_and_word_progress(self):
        self.assertEqual(self.check_system(self.system_manifest())["samples"][0]["frames"], 2)
        for key, value in [
            ("rate_multiplier", 1.0),
            ("status", "rendering"),
            ("shared_product_renderer", False),
            ("route", "host-avspeech-write"),
        ]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.check_system(self.system_manifest() | {key: value})
        for key, value in [
            ("frames", 3),
            ("sample_rate", 44_100),
            ("duration_seconds", 1.0),
            ("status", "failed"),
            ("marks", []),
            ("marks", [{"text": "Am", "start": 0, "end": 2 / 24_000}]),
            ("marks", [{"text": "Am Montag.", "start": 0, "end": float("nan")}]),
            ("marks", [{"text": "Am Montag.", "start": 0, "end": 2.0}]),
            (
                "marks",
                [
                    {"text": "Am", "start": 1 / 24_000, "end": 2 / 24_000},
                    {"text": "Montag.", "start": 0, "end": 1 / 24_000},
                ],
            ),
        ]:
            manifest = self.system_manifest()
            manifest["samples"][0][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                self.check_system(manifest)

    def test_failed_voice_keeps_process_logs_and_partial_manifest_without_entering_comparison(self):
        folder = self.root / "voice"
        folder.mkdir()
        raw = json.dumps({"status": "rendering", "samples": []})
        (folder / "manifest.json").write_text(raw)
        result = subprocess.CompletedProcess([], 1, "progress", "synthetic error")
        with patch.object(listening.subprocess, "run", return_value=result):
            manifest, failure = listening.render_voice(
                ["synthetic"], folder, {"date": "Am Montag."}, system=True
            )
        self.assertIsNone(manifest)
        self.assertEqual(failure["manifest_sha256"], listening.sha(folder / "manifest.json"))
        self.assertEqual((folder / "manifest.json").read_text(), raw)
        self.assertEqual((self.root / "voice.stderr.log").read_text(), "synthetic error")
        self.assertEqual((self.root / "voice.stdout.log").read_text(), "progress")
        self.assertEqual(json.loads((self.root / "voice.failure.json").read_text()), failure)

    def test_timed_out_voice_retains_partial_byte_logs(self):
        folder = self.root / "voice"
        error = subprocess.TimeoutExpired(["synthetic"], 600, output=b"partial", stderr=b"timeout")
        with patch.object(listening.subprocess, "run", side_effect=error):
            manifest, failure = listening.render_voice(["synthetic"], folder, {})
        self.assertIsNone(manifest)
        self.assertTrue(failure["process"]["timeout"])
        self.assertEqual((self.root / "voice.stdout.log").read_text(), "partial")

    @unittest.skipUnless(
        sys.platform == "darwin" and shutil.which("swiftc"), "Swift host export probe"
    )
    def test_shared_pcm_export_is_canonical_pcm16_with_bounded_quantization(self):
        repository = Path(__file__).resolve().parents[4]
        binary = self.root / "export-probe"
        result = self.root / "export.wav"
        subprocess.run(
            [
                "swiftc",
                "-swift-version",
                "6",
                "-strict-concurrency=complete",
                "-parse-as-library",
                "-module-cache-path",
                str(self.root / "modules"),
                str(repository / "apps/ios/Features/Conversation/OutputAudio.swift"),
                str(Path(__file__).parents[1] / "SpeechSampleFile.swift"),
                str(Path(__file__).with_name("SpeechSampleFileProbe.swift")),
                "-o",
                str(binary),
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=120,
        )
        subprocess.run([binary, result], check=True, capture_output=True, text=True, timeout=30)
        with wave.open(str(result)) as audio:
            self.assertEqual(
                (audio.getnchannels(), audio.getframerate(), audio.getsampwidth()), (1, 24_000, 2)
            )
            self.assertEqual(audio.getnframes(), 7)
            self.assertEqual(
                struct.unpack("<7h", audio.readframes(7)),
                (-32767, -32767, -16384, 0, 16384, 32767, 32767),
            )
        self.assertEqual(len(result.read_bytes()), 44 + 7 * 2)


if __name__ == "__main__":
    unittest.main()
