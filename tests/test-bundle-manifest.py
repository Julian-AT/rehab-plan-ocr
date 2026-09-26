#!/usr/bin/env python3
"""Keep bundled notices complete and consistent with pinned speech resources."""

import hashlib
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class BundleManifestTests(unittest.TestCase):
    def test_every_notice_has_its_current_checksum(self):
        directory = ROOT / "licenses"
        manifest = json.loads((directory / "manifest.json").read_text())
        actual = {
            path.name: hashlib.sha256(path.read_bytes()).hexdigest()
            for path in directory.iterdir()
            if path.is_file() and path.name != "manifest.json"
        }
        self.assertEqual(manifest, actual)

    def test_speech_notice_and_license_match_the_locked_bundle(self):
        manifest = json.loads((ROOT / "models/kokoro.lock.json").read_text())
        entries = {entry["path"]: entry for entry in manifest["files"]}
        for source, destination in [
            ("kokoro-source.txt", "NOTICE"),
            ("kokoro-apache-2.0.txt", "LICENSE"),
        ]:
            with self.subTest(source=source):
                data = (ROOT / "licenses" / source).read_bytes()
                self.assertEqual(hashlib.sha256(data).hexdigest(), entries[destination]["sha256"])
                self.assertEqual(len(data), entries[destination]["bytes"])


if __name__ == "__main__":
    unittest.main()
