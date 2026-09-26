"""Model restoration must honor committed pins and never rewrite them implicitly."""

import hashlib
import importlib.util
import json
import os
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
        self.assets = self.root / ".local/models/runtime/small"
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
        self.lock = self.root / "ml/registry/runtime/small.lock.json"
        self.lock.parent.mkdir(parents=True, exist_ok=True)
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

    def test_verified_repeats_preserve_every_resource_and_pin_timestamp(self):
        with patch.object(MODULE, "fetch", return_value=self.content):
            self.run_restore()
        paths = [self.lock, *self.assets.iterdir()]
        for path in paths:
            os.utime(path, ns=(1_000_000_000, 1_000_000_000))
        before = {path: (path.read_bytes(), path.stat().st_mtime_ns) for path in paths}
        with patch.object(MODULE, "fetch", side_effect=AssertionError("network access")):
            self.run_restore()
            self.run_restore("--offline")
        self.assertEqual(
            {path: (path.read_bytes(), path.stat().st_mtime_ns) for path in paths}, before
        )

    def test_failed_metadata_publication_preserves_existing_resource(self):
        (self.assets / "rec-inference.yml").write_bytes(self.content)
        dictionary = self.assets / "dictionary.json"
        dictionary.write_bytes(b"previous incomplete dictionary")
        with patch.object(Path, "replace", side_effect=OSError("interrupted publication")):
            with self.assertRaisesRegex(OSError, "interrupted publication"):
                self.run_restore("--offline")
        self.assertEqual(dictionary.read_bytes(), b"previous incomplete dictionary")
        self.assertEqual(self.lock.read_bytes(), self.original)
        self.assertFalse(list(self.assets.glob(".dictionary.json-*")))

    def test_metadata_remains_readable_and_repair_preserves_existing_permissions(self):
        with patch.object(MODULE, "fetch", return_value=self.content):
            self.run_restore()
        dictionary = self.assets / "dictionary.json"
        manifest = self.assets / "manifest.json"
        self.assertEqual(dictionary.stat().st_mode & 0o777, 0o644)
        self.assertEqual(manifest.stat().st_mode & 0o777, 0o644)
        dictionary.write_bytes(b"damaged dictionary")
        dictionary.chmod(0o640)
        self.run_restore("--offline")
        self.assertEqual(dictionary.read_bytes(), self.dictionary)
        self.assertEqual(dictionary.stat().st_mode & 0o777, 0o640)

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
