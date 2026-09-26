"""Model restoration must honor committed pins and never rewrite them implicitly."""

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "fetch_models", Path(__file__).resolve().parents[3] / "tooling/build/fetch-models.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class RestorationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.assets = self.root / "models/private/small"
        self.assets.mkdir(parents=True)
        self.content = b"PostProcess:\n  character_dict: ['a', 'b']\n"
        self.dictionary = json.dumps(["", "a", "b", " "], ensure_ascii=False).encode()
        self.manifest = {
            "files": [
                {
                    "path": "rec-inference.yml",
                    "url": "https://invalid.example/pinned/config",
                    "sha256": hashlib.sha256(self.content).hexdigest(),
                    "bytes": len(self.content),
                }
            ],
            "dictionary_sha256": hashlib.sha256(self.dictionary).hexdigest(),
        }
        self.lock = self.root / "models/small.lock.json"
        self.lock.write_text(json.dumps(self.manifest, separators=(",", ":")))
        self.original = self.lock.read_bytes()
        self.modified = self.lock.stat().st_mtime_ns

    def run_restore(self, *args):
        with patch.object(MODULE, "ROOT", self.root), patch("sys.argv", ["fetch", *args]):
            MODULE.main()

    def test_download_and_offline_verification_leave_lock_bytes_and_timestamp_intact(self):
        with patch.object(MODULE, "fetch", return_value=self.content) as fetch:
            self.run_restore()
            fetch.assert_called_once()
        with patch.object(MODULE, "fetch", side_effect=AssertionError("network access")):
            self.run_restore("--offline")
        self.assertEqual(self.lock.read_bytes(), self.original)
        self.assertEqual(self.lock.stat().st_mtime_ns, self.modified)
        self.assertEqual((self.assets / "dictionary.json").read_bytes(), self.dictionary)

    def test_corrupt_download_does_not_replace_existing_asset_or_pin(self):
        target = self.assets / "rec-inference.yml"
        target.write_bytes(b"previous interrupted asset")
        with patch.object(MODULE, "fetch", return_value=b"wrong"):
            with self.assertRaisesRegex(SystemExit, "Checksum mismatch"):
                self.run_restore()
        self.assertEqual(target.read_bytes(), b"previous interrupted asset")
        self.assertEqual(self.lock.read_bytes(), self.original)

    def test_offline_missing_asset_never_downloads(self):
        with patch.object(MODULE, "fetch", side_effect=AssertionError("network access")):
            with self.assertRaisesRegex(SystemExit, "Missing or corrupt"):
                self.run_restore("--offline")

    def test_unpinned_dictionary_cannot_be_silently_regenerated(self):
        self.manifest["dictionary_sha256"] = "unknown"
        self.lock.write_text(json.dumps(self.manifest))
        (self.assets / "rec-inference.yml").write_bytes(self.content)
        with self.assertRaisesRegex(SystemExit, "Dictionary differs"):
            self.run_restore("--offline")
        self.assertFalse((self.assets / "dictionary.json").exists())


if __name__ == "__main__":
    unittest.main()
