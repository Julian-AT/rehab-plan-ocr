"""A replay must use frozen inputs, preserve originals and make no accuracy claim."""

import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "ml/evaluation/recognition"))
spec = importlib.util.spec_from_file_location(
    "replay", ROOT / "ml/evaluation/recognition/replay-baseline.py"
)
replay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(replay)


class BaselineReplayTests(unittest.TestCase):
    def fixture(self, root):
        frozen, models, data = [root / name for name in ["frozen", "models", "data"]]
        for folder in [frozen, models, data / "raw"]:
            folder.mkdir(parents=True)
        ((frozen / "reha").resolve()).write_bytes(b"frozen-executable")
        ((frozen / "config.json").resolve()).write_text("{}")
        (models / "manifest.json").write_text("{}")
        source = data / "raw/synthetic.png"
        source.write_bytes(b"invented-photo")
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        (data / "inventory.json").write_text(
            json.dumps({"entries": [{"filename": source.name, "sha256": digest}]})
        )
        manifest = {"created_at": "2026-09-11T00:00:00Z"}
        for path, key in [
            (frozen / "reha", "binary_sha256"),
            (frozen / "config.json", "config_sha256"),
            (models / "manifest.json", "model_manifest_sha256"),
            (data / "inventory.json", "inventory_sha256"),
        ]:
            manifest[key] = replay.sha(path)
        (frozen / "baseline.json").write_text(json.dumps(manifest))
        return frozen, models, data

    def test_frozen_inputs_and_unconfirmed_status(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            frozen, models, data = self.fixture(root)

            def scan(command, **_):
                self.assertEqual(Path(command[0]), (frozen / "reha").resolve())
                self.assertEqual(Path(command[-1]), (frozen / "config.json").resolve())
                (Path(command[3]) / "run.json").write_text(
                    json.dumps({"total_ms": 123, "appointments": []})
                )
                return type("Result", (), {"returncode": 0})()

            with (
                patch.object(replay.subprocess, "run", side_effect=scan),
                patch.object(replay.platform, "platform", return_value="test-host"),
            ):
                report = replay.replay(frozen, models, data, root / "output")
            self.assertFalse(report["verified_accuracy"])
            self.assertFalse(report["physical_iphone_measurement"])
            self.assertEqual(report["timing_ms"]["median"], 123)
            self.assertEqual((data / "raw/synthetic.png").read_bytes(), b"invented-photo")
            with self.assertRaises(FileExistsError):
                replay.replay(frozen, models, data, root / "output")

    def test_changed_frozen_executable_is_rejected_before_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            frozen, models, data = self.fixture(root)
            ((frozen / "reha").resolve()).write_bytes(b"replacement")
            with self.assertRaisesRegex(ValueError, "binary_sha256"):
                replay.replay(frozen, models, data, root / "output")
            self.assertFalse((root / "output").exists())


if __name__ == "__main__":
    unittest.main()
