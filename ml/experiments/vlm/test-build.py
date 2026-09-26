"""Reject ambiguous source identity and writes into existing or foreign evidence."""

import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("vlm_build", Path(__file__).with_name("build.py"))
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)
QUALIFY_SPEC = importlib.util.spec_from_file_location(
    "vlm_qualify", Path(__file__).with_name("qualify-vlm.py")
)
qualifier = importlib.util.module_from_spec(QUALIFY_SPEC)
QUALIFY_SPEC.loader.exec_module(qualifier)


class BuildGuards(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.source = self.root / builder.SOURCE
        self.source.mkdir(parents=True)
        self.git("init", "--quiet")
        (self.source / "source").write_text("pinned\n")
        self.git("add", "source")
        self.git(
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "-c",
            "commit.gpgsign=false",
            "commit",
            "--quiet",
            "-m",
            "fixture",
        )
        self.revision = self.git("rev-parse", "HEAD").strip()
        lock = self.root / builder.LOCK
        lock.parent.mkdir(parents=True)
        lock.write_text(
            json.dumps(
                {
                    "runtime": {
                        "revision": self.revision,
                        "repository": "https://example.invalid/runtime",
                    }
                }
            )
        )

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.source), *args], text=True)

    def test_clean_pin_is_accepted_but_tracked_and_untracked_changes_are_rejected(self):
        self.assertEqual(builder.verify_source(self.root), self.revision)
        (self.source / "source").write_text("modified\n")
        with self.assertRaisesRegex(ValueError, "pinned clean"):
            builder.verify_source(self.root)
        (self.source / "source").write_text("pinned\n")
        (self.source / "injected.cpp").write_text("untracked\n")
        with self.assertRaisesRegex(ValueError, "pinned clean"):
            builder.verify_source(self.root)

    def test_different_pin_is_rejected(self):
        (self.root / builder.LOCK).write_text(json.dumps({"runtime": {"revision": "0" * 40}}))
        with self.assertRaisesRegex(ValueError, "pinned clean"):
            builder.verify_source(self.root)

    def test_shared_restore_refuses_different_pin_before_starting_a_process(self):
        (self.root / "ml/registry/assistant-base.json").write_text(
            json.dumps(
                {
                    "converter_repository": "https://example.invalid/runtime",
                    "converter_revision": "other",
                }
            )
        )
        with patch.object(builder.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "Shared runtime pins differ"):
                builder.restore(self.root)
            run.assert_not_called()

    def test_existing_evidence_and_symlinked_paths_are_preserved(self):
        evidence = self.root / ".local/runs/retained"
        evidence.mkdir(parents=True)
        (evidence / "receipt.json").write_text("original")
        with self.assertRaises(FileExistsError):
            builder.build(evidence, self.root)
        self.assertEqual((evidence / "receipt.json").read_text(), "original")
        link = evidence.parent / "link"
        link.symlink_to(evidence, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "Symbolic link"):
            builder.build(link / "new", self.root)
        with self.assertRaises(ValueError):
            builder.build(self.root / "outside-runs", self.root)
        self.assertFalse((evidence / "new").exists())

    def test_conversion_cannot_rewrite_a_previous_run_or_its_symlink(self):
        existing = self.root / "previous-conversion"
        existing.mkdir()
        manifest = existing / "candidates.json"
        manifest.write_text("retained manifest")
        alias = self.root / "alias"
        alias.symlink_to(existing, target_is_directory=True)
        with patch.object(qualifier.subprocess, "check_output") as commands:
            for destination in [existing, alias]:
                with self.assertRaisesRegex(ValueError, "new output directory"):
                    qualifier.qualify(SimpleNamespace(output=destination))
            commands.assert_not_called()
        self.assertEqual(manifest.read_text(), "retained manifest")


if __name__ == "__main__":
    unittest.main()
