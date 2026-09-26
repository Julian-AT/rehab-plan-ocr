import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "migration", Path(__file__).parents[1] / "migrate-private.py"
)
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


class PrivateMigrationTests(unittest.TestCase):
    def setup_tree(self, root):
        for source in migration.MOVES:
            path = root / source
            path.mkdir(parents=True)
            (path / "original.bin").write_bytes(b"exact source bytes")
            (path / "reference").symlink_to("original.bin")
        return root / ".local/migrations/test.json"

    def test_bytes_references_external_originals_and_resume_survive(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = self.setup_tree(root)
            external = root / "external-original.bin"
            external.write_bytes(b"external unchanged")
            (root / "data/private/external").symlink_to(external)
            migration.plan(root, manifest)
            migration.apply(root, manifest)
            (root / ".local/datasets/private/new-reference.json").write_text('{"review":"pending"}')
            migration.apply(root, manifest)
            self.assertTrue((root / "data/private/new-reference.json").is_file())
            for source, destination in migration.MOVES.items():
                self.assertTrue((root / source).is_symlink())
                self.assertEqual(
                    (root / destination / "original.bin").read_bytes(), b"exact source bytes"
                )
                self.assertEqual((root / source / "reference").read_bytes(), b"exact source bytes")
            self.assertEqual(external.read_bytes(), b"external unchanged")

    def test_changed_source_and_existing_destination_are_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = self.setup_tree(root)
            migration.plan(root, manifest)
            (root / "data/private/original.bin").write_bytes(b"new edit")
            with self.assertRaises(ValueError):
                migration.apply(root, manifest)
            self.assertEqual((root / "data/private/original.bin").read_bytes(), b"new edit")
            (root / ".local/datasets/private").mkdir(parents=True)
            with self.assertRaises(ValueError):
                migration.apply(root, manifest)

    def test_interruption_after_rename_resumes_without_losing_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = self.setup_tree(root)
            migration.plan(root, manifest)
            new = root / ".local/datasets/private"
            new.parent.mkdir(parents=True)
            (root / "data/private").rename(new)
            migration.apply(root, manifest)
            self.assertEqual(
                (root / "data/private/original.bin").read_bytes(), b"exact source bytes"
            )

    def test_post_move_mismatch_restores_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = self.setup_tree(root)
            migration.plan(root, manifest)
            expected = json.loads(manifest.read_text())["moves"]["data/private"]["entries"]
            with patch.object(migration, "inventory", side_effect=[expected, {}]):
                with self.assertRaises(ValueError):
                    migration.apply(root, manifest)
            self.assertFalse((root / "data/private").is_symlink())
            self.assertEqual(
                (root / "data/private/original.bin").read_bytes(), b"exact source bytes"
            )

    def test_wrong_compatibility_link_is_never_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = self.setup_tree(root)
            migration.plan(root, manifest)
            new = root / ".local/datasets/private"
            new.parent.mkdir(parents=True)
            (root / "data/private").rename(new)
            (root / "data/private").symlink_to("missing")
            with self.assertRaises(ValueError):
                migration.apply(root, manifest)
            self.assertEqual((new / "original.bin").read_bytes(), b"exact source bytes")


if __name__ == "__main__":
    unittest.main()
