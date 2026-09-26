import importlib.util
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1]))
spec = importlib.util.spec_from_file_location(
    "model_objects", Path(__file__).parents[1] / "model_objects.py"
)
objects = importlib.util.module_from_spec(spec)
spec.loader.exec_module(objects)


class ModelObjectTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.paths = [
            self.root / f".local/runs/assistant-{n}/baseline.gguf" for n in ["one", "two"]
        ]
        for path in self.paths:
            path.parent.mkdir(parents=True)
            path.write_bytes(b"GGUF immutable model")
        pin = self.root / objects.PIN
        pin.parent.mkdir(parents=True)
        pin.write_text(json.dumps({"artifact": objects.identity(self.paths[0])}))
        self.checkpoint = self.paths[0].parent / "checkpoints/epoch-0001/optimizer"
        self.checkpoint.parent.mkdir(parents=True)
        self.checkpoint.write_bytes(b"mutable training state")
        self.manifest = self.root / ".local/maintenance/objects.json"
        self.guard = patch.object(objects, "guard")
        self.guard.start()
        self.addCleanup(self.guard.stop)
        self.clone = patch.object(objects, "clone", side_effect=shutil.copy2)
        self.clone.start()
        self.addCleanup(self.clone.stop)

    def test_preserves_paths_content_separate_inodes_and_checkpoints(self):
        objects.plan(self.root, self.manifest)
        result = objects.apply(self.root, self.manifest)
        self.assertEqual(result["preserved_paths"], 2)
        self.assertEqual(objects.apply(self.root, self.manifest), result)
        stored = list((self.root / ".local/objects/sha256").glob("*.gguf"))
        files = self.paths + stored
        self.assertEqual(len({p.stat().st_ino for p in files}), 3)
        self.assertTrue(all(p.read_bytes() == b"GGUF immutable model" for p in files))
        self.paths[0].chmod(0o644)
        self.paths[0].write_bytes(b"independent replacement")
        self.assertEqual(stored[0].read_bytes(), b"GGUF immutable model")
        self.assertEqual(self.paths[1].read_bytes(), b"GGUF immutable model")
        self.assertEqual(self.checkpoint.read_bytes(), b"mutable training state")

    def test_changed_model_and_protected_path_refuse_replacement(self):
        value = objects.plan(self.root, self.manifest)
        self.paths[0].write_bytes(b"changed")
        with self.assertRaises(ValueError):
            objects.apply(self.root, self.manifest)
        value["groups"][0]["paths"][0] = str(self.checkpoint.relative_to(self.root))
        self.manifest.write_text(json.dumps(value))
        with self.assertRaises(ValueError):
            objects.apply(self.root, self.manifest)

    def test_interruption_and_unsupported_cloning_preserve_models(self):
        objects.plan(self.root, self.manifest)
        with patch.object(objects, "clone", side_effect=OSError("no clone support")):
            with self.assertRaises(OSError):
                objects.apply(self.root, self.manifest)
        self.assertTrue(all(p.read_bytes() == b"GGUF immutable model" for p in self.paths))
        real_clone = objects.verified_clone
        calls = 0

        def interrupted(source, destination, expected):
            nonlocal calls
            real_clone(source, destination, expected)
            calls += 1
            if calls == 2:
                raise KeyboardInterrupt()

        with patch.object(objects, "verified_clone", side_effect=interrupted):
            with self.assertRaises(KeyboardInterrupt):
                objects.apply(self.root, self.manifest)
        self.assertEqual(objects.apply(self.root, self.manifest)["preserved_paths"], 2)


if __name__ == "__main__":
    unittest.main()
