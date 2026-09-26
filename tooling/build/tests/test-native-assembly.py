"""Native cache failure/recovery tests use tiny generated archives, never real assets."""

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "assembly", Path(__file__).resolve().parents[1] / "assemble-native.py"
)
assembly = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(assembly)


class NativeAssemblyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.count = 0
        self.identity = {"source": "one", "toolchain": "two", "triple": "sim", "models": "three"}

    def produce(self, staging):
        self.count += 1
        (staging / "library").write_bytes(b"complete archive")

    def build(self, identity=None, produce=None):
        return assembly.cached_build(
            self.root, identity or self.identity, ["library"], produce or self.produce
        )

    def test_unchanged_build_keeps_product_and_package_timestamps(self):
        product = self.build()
        link = self.root / "package"
        assembly.publish_link(link, product)
        before = ((product / "library").stat().st_mtime_ns, link.lstat().st_mtime_ns)
        self.assertEqual(self.build(), product)
        assembly.publish_link(link, product)
        self.assertEqual(
            before, ((product / "library").stat().st_mtime_ns, link.lstat().st_mtime_ns)
        )
        self.assertEqual(self.count, 1)

    def test_each_identity_dimension_invalidates_cache(self):
        original = self.build()
        for dimension in self.identity:
            changed = self.identity | {dimension: "changed"}
            self.assertNotEqual(self.build(changed), original)
        self.assertEqual(self.count, 1 + len(self.identity))

    def test_corrupt_missing_extra_and_symlink_outputs_are_rebuilt(self):
        product = self.build()
        (product / "library").write_bytes(b"corrupt")
        self.build()
        (product / "library").unlink()
        self.build()
        (product / "extra").write_bytes(b"unexpected")
        self.build()
        (product / "alias").symlink_to("library")
        self.build()
        self.assertEqual(self.count, 5)
        self.assertEqual((product / "library").read_bytes(), b"complete archive")

    def test_failed_rebuild_keeps_old_artifact_and_does_not_publish_partial(self):
        product = self.build()
        (product / "library").write_bytes(b"damaged old archive")

        def fail(staging):
            (staging / "library").write_bytes(b"partial")
            raise RuntimeError("interrupted")

        with self.assertRaisesRegex(RuntimeError, "interrupted"):
            self.build(produce=fail)
        self.assertEqual((product / "library").read_bytes(), b"damaged old archive")
        self.assertFalse(list(self.root.glob(".assembly-*")))
        self.build()
        self.assertEqual((product / "library").read_bytes(), b"complete archive")

    def test_missing_required_artifact_does_not_create_cache_entry(self):
        with self.assertRaisesRegex(ValueError, "required artifact"):
            self.build(produce=lambda _: None)
        self.assertFalse((self.root / assembly.key(self.identity)).exists())

    def test_symbol_check_requires_api_and_rejects_unrelated_tool_errors(self):
        diagnostic = (
            "nm: error: file.o: Unknown attribute kind (105) (Producer: 'LLVM22-rust-1.98')"
        )
        result = subprocess.CompletedProcess([], 1, "000001 T _OrtGetApiBase\n", diagnostic)
        assembly.check_symbols(result)
        result.stdout = "000001 U _OrtGetApiBase\n"
        with self.assertRaisesRegex(ValueError, "missing ONNX"):
            assembly.check_symbols(result)
        result.stdout = "000001 T _OrtGetApiBase\n"
        result.stderr += "\nnm: truncated object"
        with self.assertRaisesRegex(ValueError, "Cannot inspect"):
            assembly.check_symbols(result)

    def test_initial_directory_migration_rolls_back_failed_publication(self):
        destination = self.root / "package"
        destination.mkdir()
        (destination / "old").write_bytes(b"old complete artifact")
        product = self.build()
        with patch.object(Path, "replace", side_effect=OSError("cannot publish")):
            with self.assertRaisesRegex(OSError, "cannot publish"):
                assembly.publish_link(destination, product)
        self.assertFalse(destination.is_symlink())
        self.assertEqual((destination / "old").read_bytes(), b"old complete artifact")
        assembly.publish_link(destination, product)
        self.assertTrue(destination.is_symlink())
        self.assertEqual((destination / "library").read_bytes(), b"complete archive")
        self.assertFalse(list(self.root.glob(".package*")))


if __name__ == "__main__":
    unittest.main()
