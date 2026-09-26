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

    def test_internal_symlink_chain_to_external_interpreter_keeps_its_target(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            manifest = self.setup_tree(root)
            interpreter = root / "external-interpreter"
            interpreter.write_bytes(b"unchanged external executable")
            source = root / "data/private"
            (source / "python").symlink_to(interpreter)
            (source / "python3").symlink_to("python")
            migration.plan(root, manifest)
            migration.apply(root, manifest)
            self.assertEqual((source / "python3").resolve(), interpreter)
            self.assertEqual(interpreter.read_bytes(), b"unchanged external executable")

    def test_direct_external_relative_symlink_still_requires_explicit_mapping(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = self.setup_tree(root)
            (root / "data/private/escaping").symlink_to("../../outside")
            with self.assertRaisesRegex(ValueError, "External relative symlink"):
                migration.plan(root, manifest)

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

    def external_source_parent(self, root, external):
        (root / "data").rename(external)
        (root / "data").symlink_to(external, target_is_directory=True)

    def assert_external_source_preserved(self, root, external):
        self.assertFalse((external / "private").is_symlink())
        self.assertEqual((external / "private/original.bin").read_bytes(), b"exact source bytes")
        self.assertFalse((root / ".local/datasets/private").exists())

    def test_external_source_parent_is_rejected_before_inventory(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory).resolve()
            root = base / "workspace"
            manifest = self.setup_tree(root)
            external = base / "external"
            self.external_source_parent(root, external)
            with patch.object(migration, "inventory", return_value={}) as inventory:
                with self.assertRaisesRegex(ValueError, "Source parent"):
                    migration.plan(root, manifest)
                inventory.assert_not_called()
            self.assert_external_source_preserved(root, external)
            self.assertFalse(manifest.exists())

    def test_source_parent_replaced_after_inventory_is_rejected_before_move(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory).resolve()
            root = base / "workspace"
            manifest = self.setup_tree(root)
            migration.plan(root, manifest)
            before = manifest.read_bytes()
            external = base / "external"
            self.external_source_parent(root, external)
            with self.assertRaisesRegex(ValueError, "Source parent"):
                migration.apply(root, manifest)
            self.assert_external_source_preserved(root, external)
            self.assertEqual(manifest.read_bytes(), before)

    def test_source_parent_changed_during_preflight_is_rechecked_before_rename(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory).resolve()
            root = base / "workspace"
            manifest = self.setup_tree(root)
            migration.plan(root, manifest)
            external = base / "external"
            real = migration.inventory

            def changed(path):
                value = real(path)
                if path == root / "data/private":
                    self.external_source_parent(root, external)
                return value

            with patch.object(migration, "inventory", side_effect=changed):
                with self.assertRaisesRegex(ValueError, "Source parent"):
                    migration.apply(root, manifest)
            self.assert_external_source_preserved(root, external)


if __name__ == "__main__":
    unittest.main()
