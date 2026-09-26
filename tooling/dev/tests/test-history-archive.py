"""Recovery requires a unique mapped path and verifies the actual retained bytes."""

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "history_archive", Path(__file__).resolve().parents[1] / "history_archive.py"
)
archive = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(archive)


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / "workspace").mkdir()
        (self.root / "workspace/evidence.json").write_bytes(b"original evidence")
        (self.root / "recovery.json").write_text(
            json.dumps({"workspace": "workspace", "path_map": "paths.json"})
        )
        self.mapping({"evidence.json": ".local/runs/record/evidence.json"})

    def mapping(self, value):
        (self.root / "paths.json").write_text(json.dumps(value))

    def test_locates_and_hashes_original_without_writing_it(self):
        result = archive.locate(
            self.root,
            "archive:workspace/.local/runs/record/evidence.json",
            hashlib.sha256(b"original evidence").hexdigest(),
        )
        self.assertEqual(result.read_bytes(), b"original evidence")
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            archive.locate(self.root, ".local/runs/record/evidence.json", "0" * 64)

    def test_rejects_unknown_ambiguous_and_escaping_paths(self):
        for name in ["missing", "../evidence.json", "/evidence.json"]:
            with self.assertRaises(ValueError):
                archive.locate(self.root, name)
        self.mapping({"evidence.json": "same", "duplicate.json": "same"})
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            archive.locate(self.root, "same")
        (self.root / "workspace/outside").symlink_to(self.root / "paths.json")
        self.mapping({"outside": "outside"})
        with self.assertRaisesRegex(ValueError, "outside"):
            archive.locate(self.root, "outside")


if __name__ == "__main__":
    unittest.main()
