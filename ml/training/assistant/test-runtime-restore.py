"""Isolated fake Git proves pinned runtime source publication survives interruption."""

import fcntl
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import runtime


class RuntimeRestoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.source = self.root / "upstream/llama.cpp"
        self.registry = self.root / "registry.json"
        self.pin = {
            "converter_repository": "https://invalid.example/fixture",
            "converter_revision": "a" * 40,
        }
        self.registry.write_text(json.dumps(self.pin))
        self.created = []

    def invoke(self, fail_at=None, collision=False, interruption=False):
        def command(args, **kwargs):
            if "clone" in args:
                path = Path(args[-1])
                path.mkdir(exist_ok=True)
                self.created.append(path)
                (path / "fixture.marker").write_text("owned staging")
            elif "checkout" in args:
                (Path(args[2]) / "checked-out").write_text(self.pin["converter_revision"])
                if collision:
                    self.source.mkdir(exist_ok=True)
                    (self.source / "foreign").write_text("preserve")
            elif "rev-parse" in args:
                marker = Path(args[2]) / "checked-out"
                if not marker.exists():
                    raise subprocess.CalledProcessError(128, args)
                return marker.read_text()
            elif "status" in args:
                return "?? foreign" if (Path(args[2]) / "foreign").exists() else ""
            if fail_at and fail_at in args:
                if interruption:
                    raise KeyboardInterrupt()
                raise subprocess.CalledProcessError(1, args)
            return "fake cmake version"

        with (
            patch.object(runtime, "SOURCE", self.source),
            patch.object(runtime, "REGISTRY", self.registry),
            patch.object(runtime, "run", side_effect=command),
            patch.object(sys, "argv", ["runtime.py", "restore"]),
        ):
            runtime.main()

    def test_failed_checkout_keeps_staging_and_retry_publishes_fresh_verified_source(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.invoke(fail_at="checkout")
        old = self.created[0]
        self.assertNotEqual(old, self.source)
        self.assertFalse(self.source.exists())
        self.assertTrue(old.exists())
        self.invoke()
        self.assertNotEqual(old, self.created[1])
        self.assertTrue(old.exists())
        self.assertFalse(self.created[1].exists())
        self.assertEqual((self.source / "checked-out").read_text(), self.pin["converter_revision"])

    def test_interrupted_clone_is_not_published(self):
        with self.assertRaises(KeyboardInterrupt):
            self.invoke(fail_at="clone", interruption=True)
        self.assertFalse(self.source.exists())
        self.assertTrue(self.created[0].exists())

    def test_existing_incomplete_source_is_preserved(self):
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

    def test_valid_existing_source_is_verified_without_cloning(self):
        self.source.mkdir(parents=True)
        (self.source / "checked-out").write_text(self.pin["converter_revision"])
        self.invoke()
        self.assertEqual(self.created, [])

    def test_dirty_existing_source_fails_without_mutation(self):
        self.source.mkdir(parents=True)
        (self.source / "checked-out").write_text(self.pin["converter_revision"])
        (self.source / "foreign").write_text("preserve")
        with self.assertRaisesRegex(ValueError, "local changes"):
            self.invoke()
        self.assertEqual(self.created, [])
        self.assertEqual((self.source / "foreign").read_text(), "preserve")

    def test_another_restore_holds_exclusive_publication_lock(self):
        self.source.parent.mkdir(parents=True)
        with (self.source.parent / ".llama.cpp.restore.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(BlockingIOError):
                self.invoke()
        self.assertEqual(self.created, [])


if __name__ == "__main__":
    unittest.main()
