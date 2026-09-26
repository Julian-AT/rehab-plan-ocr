#!/usr/bin/env python3
"""Separate release notices from preserved experimental speech provenance."""

import hashlib
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class BundleManifestTests(unittest.TestCase):
    def test_every_notice_has_its_current_checksum(self):
        directory = ROOT / "docs/third-party/licenses"
        manifest = json.loads((directory / "manifest.json").read_text())
        actual = {
            path.name: hashlib.sha256(path.read_bytes()).hexdigest()
            for path in directory.iterdir()
            if path.is_file() and path.name != "manifest.json"
        }
        self.assertEqual(manifest, actual)

    def test_speech_notice_and_license_match_the_locked_bundle(self):
        manifest = json.loads((ROOT / "ml/registry/runtime/kokoro.lock.json").read_text())
        entries = {entry["path"]: entry for entry in manifest["files"]}
        for source, destination in [
            ("experiments/kokoro/kokoro-source.txt", "NOTICE"),
            ("licenses/apache-2.0.txt", "LICENSE"),
        ]:
            with self.subTest(source=source):
                data = (ROOT / "docs/third-party" / source).read_bytes()
                self.assertEqual(hashlib.sha256(data).hexdigest(), entries[destination]["sha256"])
                self.assertEqual(len(data), entries[destination]["bytes"])

    def test_experimental_notices_retain_the_pre_separation_identity(self):
        folder = ROOT / "docs/third-party/experiments/kokoro"
        manifest = json.loads((folder / "manifest.json").read_text())
        self.assertEqual(set(manifest), {p.name for p in folder.glob("*.txt")})
        for name, expected in manifest.items():
            self.assertEqual(hashlib.sha256((folder / name).read_bytes()).hexdigest(), expected)


if __name__ == "__main__":
    unittest.main()
