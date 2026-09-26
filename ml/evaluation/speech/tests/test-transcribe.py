"""File-ASR evidence cannot accept stale identities, cloud routes or altered audio."""

import copy
import json
import sys
import tempfile
import unittest
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import transcribe


class TranscriptTests(unittest.TestCase):
    def setUp(self):
        self.request = {"runID": "unique", "locale": "de-AT", "audioSHA256": "a" * 64}
        self.result = {
            **self.request,
            "requestedLocale": "de-AT",
            "resolvedLocale": "de_AT",
            "provider": "Apple SpeechTranscriber",
            "stage": "completed",
            "seconds": 0.5,
            "downloadRequested": False,
            "microphoneUsed": False,
            "physicalDevice": False,
            "segments": [{"start": 0, "duration": 1, "text": "Um 9:30 Uhr."}],
        }

    def test_complete_segments_and_empty_recognition_are_distinguished(self):
        self.assertEqual(transcribe.validate(self.result, self.request, 2), "Um 9:30 Uhr.")
        self.result["segments"] = []
        self.assertEqual(transcribe.validate(self.result, self.request, 2), "")

    def test_wrong_identity_incomplete_and_nonlocal_routes_fail(self):
        for change in [
            {"runID": "stale"},
            {"audioSHA256": "b" * 64},
            {"resolvedLocale": "en_US"},
            {"requestedLocale": "de-DE"},
            {"provider": "remote"},
            {"stage": "started"},
            {"downloadRequested": True},
            {"microphoneUsed": True},
            {"physicalDevice": True},
            {"seconds": float("nan")},
            {"seconds": -1},
            {"seconds": True},
        ]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                transcribe.validate(self.result | change, self.request, 2)

    def test_invalid_overlapping_and_out_of_file_timestamps_fail(self):
        for segments in [
            [{"start": -1, "duration": 1, "text": "x"}],
            [{"start": 0, "duration": 3, "text": "x"}],
            [{"start": 0, "duration": 1, "text": 123}],
            [{"start": 0, "duration": float("inf"), "text": "x"}],
            [{"start": 0, "duration": 1, "text": "x"}, {"start": 0.5, "duration": 1, "text": "x"}],
        ]:
            with self.subTest(segments=segments), self.assertRaises(ValueError):
                transcribe.validate(self.result | {"segments": segments}, self.request, 2)


class CorpusTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        prompts = json.loads((transcribe.HERE / "prompts.json").read_text())["samples"]
        key = {}
        for voice in ["a", "b"]:
            folder = self.root / voice
            folder.mkdir()
            samples = []
            for prompt in prompts:
                path = folder / (prompt["id"] + ".wav")
                with wave.open(str(path), "wb") as output:
                    output.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
                    output.writeframes(b"\x10\x01" * 100)
                samples.append(
                    dict(
                        transcribe.audio_identity(path),
                        id=prompt["id"],
                        spoken_text=prompt["text"],
                        path=path.name,
                    )
                )
            key[voice] = {"folder": voice, "manifest": {"samples": samples}}
        self.manifest = {
            "source_identities": {
                "ml/evaluation/speech/prompts.json": transcribe.sha(
                    transcribe.HERE / "prompts.json"
                )
            },
            "human_listening_completed": False,
            "shipping_ios_route": False,
            "voices": 2,
            "rendered_samples": 20,
            "key": key,
        }

    def check(self, manifest):
        (self.root / "manifest.json").write_text(json.dumps(manifest))
        return transcribe.samples(self.root)

    def test_all_audio_bytes_and_counts_are_verified(self):
        self.assertEqual(len(self.check(self.manifest)), 20)
        (self.root / "a/date.wav").write_bytes((self.root / "a/date.wav").read_bytes()[:-2])
        with self.assertRaises(ValueError):
            self.check(self.manifest)

    def test_changed_words_missing_cases_and_escaping_paths_fail(self):
        for change in [
            lambda m: m["key"]["b"]["manifest"]["samples"][0].update(spoken_text="different"),
            lambda m: m["key"]["b"]["manifest"]["samples"].pop(),
            lambda m: m["key"]["b"]["manifest"]["samples"][0].update(path="../a/date.wav"),
            lambda m: m.update(rendered_samples=21),
        ]:
            manifest = copy.deepcopy(self.manifest)
            change(manifest)
            with self.assertRaises(ValueError):
                self.check(manifest)


if __name__ == "__main__":
    unittest.main()
