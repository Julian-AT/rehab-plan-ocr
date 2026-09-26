"""Experimental app comparisons must load exactly the selected registered artifact."""

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "assistant_trial_builder", Path(__file__).parents[1] / "build-assistant-trial.py"
)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class TrialModelTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        patcher = patch.object(builder, "ROOT", self.root)
        patcher.start()
        self.addCleanup(patcher.stop)
        (self.root / "ml/registry").mkdir(parents=True)
        (self.root / ".local/runs/example").mkdir(parents=True)
        self.paths = {}
        for variant, name in [
            ("tuned", "assistant-development-001"),
            ("untuned", "assistant-untuned-001"),
        ]:
            model = self.root / ".local/runs/example" / (variant + ".gguf")
            data = ("invented model " + variant).encode()
            model.write_bytes(data)
            registry = dict(
                schema_version=1,
                id=name,
                qualified=False,
                artifact=dict(
                    format="GGUF-F16",
                    path=str(model.relative_to(self.root)),
                    bytes=len(data),
                    sha256=hashlib.sha256(data).hexdigest(),
                ),
            )
            path = self.root / "ml/registry" / (name + ".json")
            path.write_text(json.dumps(registry))
            self.paths[variant] = path

    def test_variants_use_distinct_registered_model_bytes(self):
        tuned = builder.model_artifact("tuned")
        baseline = builder.model_artifact("untuned")
        self.assertNotEqual(tuned[1]["id"], baseline[1]["id"])
        self.assertNotEqual(tuned[2].read_bytes(), baseline[2].read_bytes())
        with self.assertRaises(ValueError):
            builder.model_artifact("../unknown")

    def test_corrupt_or_replaced_artifacts_fail(self):
        _, _, model = builder.model_artifact("untuned")
        model.write_bytes(b"unrelated bytes")
        with self.assertRaises(ValueError):
            builder.model_artifact("untuned")

    def test_promoted_wrong_format_wrong_size_and_escaped_paths_fail(self):
        path = self.paths["tuned"]
        original = json.loads(path.read_text())
        for changes in [
            {"qualified": True},
            {"schema_version": 2},
            {"id": ""},
            {"artifact": dict(original["artifact"], format="unknown")},
            {"artifact": dict(original["artifact"], bytes=True)},
            {"artifact": dict(original["artifact"], bytes=500)},
            {"artifact": dict(original["artifact"], path="../../outside.gguf")},
        ]:
            path.write_text(json.dumps(dict(original, **changes)))
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                builder.model_artifact("tuned")

    def test_private_path_symlink_cannot_escape_into_other_storage(self):
        _, _, model = builder.model_artifact("untuned")
        outside = self.root / "unrelated.gguf"
        model.rename(outside)
        model.symlink_to(outside)
        with self.assertRaises(ValueError):
            builder.model_artifact("untuned")


if __name__ == "__main__":
    unittest.main()
