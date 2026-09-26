"""Tiny fake checkpoints preserve the original pinned-download provenance."""

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

HERE = Path(__file__).resolve().parent


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


fetcher = load("vlm_fetch_fixture", HERE / "fetch-vlm.py")
qualifier = load("vlm_qualify_fixture", HERE / "qualify-vlm.py")


class SourceProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.candidate = {
            "id": "paddleocr-vl-1.6",
            "repository": "fixture/model",
            "revision": "a" * 40,
            "files": [{"path": "config.json", "bytes": 4, "sha256": None}],
        }
        self.lock = {"candidates": [self.candidate], "runtime": {"revision": "b" * 40}}
        self.destination = self.root / "checkpoints"
        self.directory = self.destination / self.candidate["id"]

    def existing(self, manifest=True):
        self.directory.mkdir(parents=True)
        (self.directory / "config.json").write_bytes(b"GOOD")
        if manifest:
            value = self.candidate | {
                "files": [
                    self.candidate["files"][0] | {"sha256": hashlib.sha256(b"GOOD").hexdigest()}
                ]
            }
            (self.directory / "source-manifest.json").write_text(json.dumps(value) + "\n")

    def test_existing_unpinned_file_without_receipt_cannot_be_newly_attested(self):
        self.existing(manifest=False)
        with patch.object(fetcher.subprocess, "run") as download:
            with self.assertRaisesRegex(ValueError, "new.*destination"):
                fetcher.fetch(self.lock, self.destination)
        download.assert_not_called()
        self.assertFalse((self.directory / "source-manifest.json").exists())
        self.assertEqual((self.directory / "config.json").read_bytes(), b"GOOD")

    def test_same_size_mutation_cannot_replace_original_manifest_identity(self):
        self.existing()
        original = (self.directory / "source-manifest.json").read_bytes()
        (self.directory / "config.json").write_bytes(b"EVIL")
        with patch.object(fetcher.subprocess, "run") as download:
            with self.assertRaisesRegex(ValueError, "new.*destination"):
                fetcher.fetch(self.lock, self.destination)
        download.assert_not_called()
        self.assertEqual((self.directory / "source-manifest.json").read_bytes(), original)

    def test_verified_existing_receipt_is_reused_byte_for_byte(self):
        self.existing()
        receipt = self.directory / "source-manifest.json"
        before = receipt.read_bytes(), receipt.stat().st_mtime_ns
        with patch.object(fetcher.subprocess, "run") as download:
            fetcher.fetch(self.lock, self.destination)
        download.assert_not_called()
        self.assertEqual((receipt.read_bytes(), receipt.stat().st_mtime_ns), before)

    def test_first_download_is_explicitly_revision_pinned_and_records_measured_hash(self):
        def download(command, **kwargs):
            self.assertIn("/resolve/" + "a" * 40 + "/config.json?download=true", command[-3])
            Path(command[-1]).write_bytes(b"GOOD")

        with patch.object(fetcher.subprocess, "run", side_effect=download) as command:
            fetcher.fetch(self.lock, self.destination)
        command.assert_called_once()
        manifest = json.loads((self.directory / "source-manifest.json").read_text())
        self.assertEqual(manifest["files"][0]["sha256"], hashlib.sha256(b"GOOD").hexdigest())
        self.assertEqual(manifest["revision"], "a" * 40)

    def test_upstream_pinned_file_can_be_verified_without_creating_a_manifest(self):
        self.existing(manifest=False)
        self.candidate["files"][0]["sha256"] = hashlib.sha256(b"GOOD").hexdigest()
        with patch.object(fetcher.subprocess, "run") as download:
            fetcher.fetch(self.lock, self.destination)
        download.assert_not_called()
        self.assertFalse((self.directory / "source-manifest.json").exists())
        (self.directory / "config.json").write_bytes(b"EVIL")
        with self.assertRaises(ValueError):
            fetcher.fetch(self.lock, self.destination)

    def test_invalid_or_incomplete_manifest_is_not_repaired_from_local_bytes(self):
        self.existing()
        receipt = self.directory / "source-manifest.json"
        original = json.loads(receipt.read_text())
        invalid = [
            dict(original, revision="changed"),
            dict(original, files=[]),
            dict(original, files=original["files"] * 2),
            dict(original, files=[dict(original["files"][0], sha256=None)]),
        ]
        for value in invalid:
            receipt.write_text(json.dumps(value))
            before = receipt.read_bytes()
            with self.subTest(value=value), self.assertRaises(ValueError):
                fetcher.fetch(self.lock, self.destination)
            self.assertEqual(receipt.read_bytes(), before)

    def test_qualification_rejects_unattested_or_mutated_source_before_converter(self):
        self.existing(manifest=False)
        registry = self.root / "ml/registry/runtime/vlm-experiments.lock.json"
        registry.parent.mkdir(parents=True)
        registry.write_text(json.dumps(self.lock))
        args = SimpleNamespace(
            output=self.root / "conversion",
            runtime=self.root / "runtime",
            glm=self.root / "glm",
            paddle=self.directory,
        )
        with (
            patch.object(qualifier, "ROOT", self.root),
            patch.object(qualifier.subprocess, "check_output", side_effect=["b" * 40, ""]),
            patch.object(qualifier.subprocess, "run") as command,
            self.assertRaisesRegex(ValueError, "new.*destination"),
        ):
            qualifier.qualify(args)
        command.assert_not_called()
        self.assertFalse(args.output.exists())


if __name__ == "__main__":
    unittest.main()
