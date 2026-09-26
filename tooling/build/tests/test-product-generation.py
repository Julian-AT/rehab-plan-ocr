"""Resource removals start a fresh product while earlier bytes remain recoverable."""

import fcntl
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / "product_generation.py"
spec = importlib.util.spec_from_file_location("product_generation", SOURCE)
g = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = g
spec.loader.exec_module(g)


class ProductGenerationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="reha-product-generation-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.base = self.root / ".local/builds/ios"
        self.current = self.base / "DerivedData"
        for name in g.INPUTS:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("synthetic " + name)
        self.addCleanup(patch.stopall)
        patch.object(g.workspace, "location", return_value=self.base).start()
        self.actual_guard = g.ensure_quiet
        self.quiet = patch.object(g, "ensure_quiet").start()

    def prepare(self):
        with g.locked(self.root) as base:
            return g.prepare(self.root, base)

    def old_product(self):
        model = self.current / "Build/Products/App.app/kokoro-german/model.bin"
        model.parent.mkdir(parents=True)
        model.write_bytes(b"historical private failed product")
        outside = self.root / "untouched-original"
        outside.write_bytes(b"original bytes")
        (self.current / "external-link").symlink_to(outside)
        release = self.root / ".local/releases/released.xcarchive/app"
        release.parent.mkdir(parents=True)
        release.write_bytes(b"released product")
        return g.inventory(self.current), outside, release

    def test_stale_resources_are_preserved_instead_of_copied_into_clean_generation(self):
        original, outside, release = self.old_product()
        self.assertEqual(self.prepare(), self.current)
        self.assertEqual(set(p.name for p in self.current.iterdir()), {g.MARKER})
        receipt_path = next((self.base / "generations").glob("*/receipt.json"))
        receipt = json.loads(receipt_path.read_text())
        preserved = self.root / receipt["preserved_location"]
        self.assertEqual(g.inventory(preserved), original)
        self.assertEqual(outside.read_bytes(), b"original bytes")
        self.assertEqual(release.read_bytes(), b"released product")
        self.assertEqual(receipt["files_deleted"], 0)
        self.assertEqual(g.checked_marker(self.root), self.current)

    def test_unchanged_contract_reuses_cache_without_another_generation(self):
        self.prepare()
        (self.current / "kept-cache").write_bytes(b"normal compiler cache")
        self.prepare()
        self.assertEqual(len(list((self.base / "generations").iterdir())), 1)
        self.assertEqual((self.current / "kept-cache").read_bytes(), b"normal compiler cache")
        self.assertEqual(self.quiet.call_count, 1)

    def test_changed_project_resource_contract_rotates_again(self):
        self.prepare()
        (self.current / "product").write_bytes(b"version one")
        (self.root / "apps/ios/project.yml").write_text("resource removed")
        with self.assertRaisesRegex(ValueError, "Stale/unknown"):
            g.checked_marker(self.root)
        self.prepare()
        self.assertFalse((self.current / "product").exists())
        self.assertEqual(len(list((self.base / "generations").iterdir())), 2)
        self.assertEqual(
            next((self.base / "generations").glob("*/DerivedData/product")).read_bytes(),
            b"version one",
        )

    def test_active_consumer_aborts_before_rotation(self):
        original, _, _ = self.old_product()
        self.quiet.side_effect = ValueError("Active build process")
        with self.assertRaisesRegex(ValueError, "Active build"):
            self.prepare()
        self.assertEqual(g.inventory(self.current), original)
        self.assertFalse((self.base / "generations").exists())

    def test_crash_after_atomic_rename_resumes_without_overwrite(self):
        original, _, _ = self.old_product()
        actual = Path.rename

        def interrupted(path, target):
            actual(path, target)
            raise RuntimeError("interrupted after rename")

        with patch.object(Path, "rename", interrupted):
            with self.assertRaisesRegex(RuntimeError, "interrupted"):
                self.prepare()
        self.assertFalse(self.current.exists())
        with self.assertRaisesRegex(ValueError, "Interrupted"):
            g.checked_marker(self.root)
        self.prepare()
        self.assertEqual(
            g.inventory(next((self.base / "generations").glob("*/DerivedData"))), original
        )
        self.assertEqual(len(list((self.base / "generations").iterdir())), 1)

    def test_crash_after_new_directory_before_marker_resumes(self):
        self.old_product()
        actual = g.artifacts.write_new

        def interrupted(path, value):
            if path.name == g.MARKER:
                raise RuntimeError("interrupted before marker")
            actual(path, value)

        with patch.object(g.artifacts, "write_new", side_effect=interrupted):
            with self.assertRaisesRegex(RuntimeError, "interrupted"):
                self.prepare()
        self.assertEqual(list(self.current.iterdir()), [])
        self.prepare()
        self.assertEqual(g.checked_marker(self.root), self.current)

    def test_changed_sources_during_interruption_keep_both_generations(self):
        self.old_product()
        actual = g.artifacts.write_new

        def interrupted(path, value):
            if path.name == g.MARKER:
                raise RuntimeError("stop")
            actual(path, value)

        with patch.object(g.artifacts, "write_new", side_effect=interrupted):
            with self.assertRaises(RuntimeError):
                self.prepare()
        (self.root / "apps/ios/project.yml").write_text("changed after interruption")
        with self.assertRaisesRegex(ValueError, "Sources changed"):
            self.prepare()
        self.assertTrue(next((self.base / "generations").glob("*/DerivedData")).is_dir())
        self.assertTrue((self.base / "product-generation-pending.json").exists())

    def test_external_current_symlink_is_rejected_without_reading_originals(self):
        external = self.root / "external-simulator"
        external.mkdir()
        self.base.mkdir(parents=True)
        self.current.symlink_to(external)
        with self.assertRaisesRegex(ValueError, "Symbolic link"):
            self.prepare()
        self.assertEqual(list(external.iterdir()), [])

    def test_build_holds_lease_and_uses_stable_path_even_if_xcode_fails(self):
        def run(command, **kwargs):
            with self.assertRaises(BlockingIOError):
                with g.locked(self.root):
                    self.fail("build lease released early")
            self.assertEqual(command[-2:], ["-derivedDataPath", str(self.current)])
            return subprocess.CompletedProcess(command, 65)

        with patch.object(g.subprocess, "run", side_effect=run):
            self.assertEqual(g.build(self.root, ["xcodebuild", "build"]), 65)
        self.assertEqual(g.checked_marker(self.root), self.current)

    def test_separate_derived_data_override_and_concurrent_lease_are_refused(self):
        with self.assertRaisesRegex(ValueError, "override"):
            g.build(self.root, ["xcodebuild", "-derivedDataPath", "/outside", "build"])
        self.base.mkdir(parents=True)
        with (self.base / "product-generation.lock").open("a+") as lease:
            fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(BlockingIOError):
                self.prepare()

    def test_process_guard_allows_own_build_ancestry_but_rejects_other_builds(self):
        pid = os.getpid()
        with patch.object(
            g.subprocess,
            "check_output",
            side_effect=[
                f"{pid} 200 python\n200 100 sh\n100 1 make\n",
                f"worktree {self.root}\n",
            ],
        ):
            self.actual_guard(self.root, self.current)
        with patch.object(
            g.subprocess,
            "check_output",
            return_value=f"{pid} 1 python\n777 1 xcodebuild\n",
        ):
            with self.assertRaisesRegex(ValueError, "Active build"):
                self.actual_guard(self.root, self.current)

    def test_preserved_generation_corruption_stops_recovery(self):
        self.old_product()
        actual = Path.rename

        def interrupted(path, target):
            actual(path, target)
            raise RuntimeError("stop")

        with patch.object(Path, "rename", interrupted):
            with self.assertRaises(RuntimeError):
                self.prepare()
        payload = next(
            (self.base / "generations").glob(
                "*/DerivedData/Build/Products/App.app/kokoro-german/model.bin"
            )
        )
        payload.write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "Preserved generation differs"):
            self.prepare()
        self.assertFalse(self.current.exists())


if __name__ == "__main__":
    unittest.main()
