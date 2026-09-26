"""Interrupted fake Git restores never publish a partial pinned source checkout."""

import fcntl
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import restore


class SourceRestoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.source = self.root / ".local/upstream/PaddleOCR"
        self.pin = {"upstream": "https://invalid.example/fixture", "revision": "a" * 40}
        registry = self.root / "ml/registry/ocr-base.json"
        registry.parent.mkdir(parents=True)
        registry.write_text(json.dumps(self.pin))
        self.created = []

    def invoke(self, fail_at=None, collision=False, offline=False):
        def command(args, **kwargs):
            if args[1] == "init":
                path = Path(args[2])
                path.mkdir(exist_ok=True)
                (path / "fixture.marker").write_text("only this invocation owns staging")
                self.created.append(path)
            elif "checkout" in args:
                (Path(args[2]) / "checked-out").write_text(self.pin["revision"])
                if collision:
                    self.source.mkdir(exist_ok=True)
                    (self.source / "foreign").write_text("preserve")
            if fail_at and fail_at in args:
                raise subprocess.CalledProcessError(1, args)

        def revision(args, **kwargs):
            marker = Path(args[2]) / "checked-out"
            if not marker.exists():
                raise subprocess.CalledProcessError(128, args)
            return marker.read_text() + "\n"

        with (
            patch.object(restore, "ROOT", self.root),
            patch.object(restore, "valid", return_value=True),
            patch.object(restore.subprocess, "run", side_effect=command),
            patch.object(restore.subprocess, "check_output", side_effect=revision),
            patch.object(sys, "argv", ["restore.py", *(["--offline"] if offline else [])]),
        ):
            restore.main()

    def test_failed_fetch_keeps_private_staging_and_retry_publishes_fresh_complete_checkout(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.invoke(fail_at="fetch")
        first = self.created[0]
        self.assertNotEqual(first, self.source)
        self.assertTrue((first / "fixture.marker").exists())
        self.assertFalse(self.source.exists())
        self.invoke()
        self.assertNotEqual(first, self.created[1])
        self.assertTrue(first.exists())
        self.assertFalse(self.created[1].exists())
        self.assertEqual((self.source / "checked-out").read_text(), self.pin["revision"])

    def test_failed_checkout_is_never_published(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.invoke(fail_at="checkout")
        self.assertFalse(self.source.exists())
        self.assertTrue(self.created[0].exists())

    def test_existing_incomplete_checkout_is_preserved_without_git_initialization(self):
        self.source.mkdir(parents=True)
        (self.source / "foreign").write_text("preserve")
        with self.assertRaises(subprocess.CalledProcessError):
            self.invoke()
        self.assertEqual(self.created, [])
        self.assertEqual((self.source / "foreign").read_text(), "preserve")

    def test_foreign_target_appearing_during_restore_is_not_replaced(self):
        with self.assertRaises(FileExistsError):
            self.invoke(collision=True)
        self.assertEqual((self.source / "foreign").read_text(), "preserve")
        self.assertTrue(self.created[0].exists())

    def test_offline_missing_source_does_not_create_checkout_or_staging(self):
        with self.assertRaisesRegex(ValueError, "missing"):
            self.invoke(offline=True)
        self.assertEqual(self.created, [])
        self.assertFalse(self.source.exists())

    def test_existing_valid_source_is_verified_without_reinitialization(self):
        self.source.mkdir(parents=True)
        (self.source / "checked-out").write_text(self.pin["revision"])
        self.invoke(offline=True)
        self.assertEqual(self.created, [])

    def test_another_restore_holds_exclusive_publication_lock(self):
        self.source.parent.mkdir(parents=True)
        with (self.source.parent / ".PaddleOCR.restore.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(BlockingIOError):
                self.invoke()
        self.assertEqual(self.created, [])
        self.assertFalse(self.source.exists())


if __name__ == "__main__":
    unittest.main()
