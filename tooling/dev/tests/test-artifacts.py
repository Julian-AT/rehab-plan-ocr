import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "artifacts", Path(__file__).parents[1] / "artifacts.py"
)
artifacts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artifacts)


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.name = "apps/ios/build/DerivedData/Build/Intermediates.noindex"
        self.cache = self.root / self.name
        self.cache.mkdir(parents=True)
        (self.cache / "object").write_bytes(b"rebuildable")
        self.protected = self.root / ".local/datasets/original"
        self.protected.parent.mkdir(parents=True)
        self.protected.write_bytes(b"private original")
        policy = {
            "reserve_gib": 20,
            "protected": [".local/datasets"],
            "rebuildable": [
                {
                    "path": self.name,
                    "consumers": ["builder"],
                    "reason": "object",
                    "rebuild": "make build",
                }
            ],
        }
        path = self.root / artifacts.POLICY
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps(policy))
        self.manifest = self.root / ".local/maintenance/preview.json"
        self.guard = patch.object(artifacts, "guard")
        self.guard.start()
        self.addCleanup(self.guard.stop)
        self.command = patch.object(artifacts, "command", return_value="a" * 40)
        self.command.start()
        self.addCleanup(self.command.stop)

    def plan(self):
        return artifacts.plan(self.root, self.manifest)

    def test_preview_delete_restart_and_rebuild_preserve_originals(self):
        self.plan()
        self.assertTrue((self.cache / "object").exists())
        result = artifacts.apply(self.root, self.manifest)
        self.assertEqual(result["deleted_files"], 1)
        self.assertEqual(self.protected.read_bytes(), b"private original")
        (self.cache / "object").write_bytes(b"rebuilt later")
        self.assertEqual(artifacts.apply(self.root, self.manifest), result)
        self.assertEqual((self.cache / "object").read_bytes(), b"rebuilt later")

    def test_peak_is_additional_and_cannot_bypass_the_reserve(self):
        with patch.object(
            artifacts.shutil, "disk_usage", return_value=SimpleNamespace(free=24 * artifacts.GIB)
        ):
            self.assertEqual(artifacts.space(self.root, 4)["reserve_gib"], 20)
            for peak in [4.1, -1, float("nan"), float("inf")]:
                with self.subTest(peak=peak), self.assertRaises(ValueError):
                    artifacts.space(self.root, peak)

    def test_new_changed_and_disappeared_files_refuse_deletion(self):
        self.plan()
        (self.cache / "new").write_bytes(b"active builder")
        with self.assertRaises(ValueError):
            artifacts.apply(self.root, self.manifest)

        (self.cache / "new").unlink()
        (self.cache / "object").write_bytes(b"changed")
        with self.assertRaises(ValueError):
            artifacts.apply(self.root, self.manifest)

    def test_unexplained_disappearance_is_rejected(self):
        self.plan()
        (self.cache / "object").unlink()
        with self.assertRaisesRegex(ValueError, "disappeared without"):
            artifacts.apply(self.root, self.manifest)

    def test_changed_protected_data_refuses_deletion(self):
        self.plan()
        self.protected.write_bytes(b"new reference")
        with self.assertRaisesRegex(ValueError, "Protected files changed"):
            artifacts.apply(self.root, self.manifest)
        self.assertTrue((self.cache / "object").exists())

    def test_replaced_parent_symlink_is_rejected(self):
        self.plan()
        (self.cache / "object").unlink()
        self.cache.rmdir()
        self.cache.symlink_to(self.protected.parent, target_is_directory=True)
        with self.assertRaises(ValueError):
            artifacts.apply(self.root, self.manifest)
        self.assertTrue(self.protected.exists())

    def test_plan_cannot_target_protected_files(self):
        value = self.plan()
        value["files"][".local/datasets/original"] = artifacts.fingerprint(self.protected)
        self.manifest.write_text(json.dumps(value))
        with self.assertRaises(ValueError):
            artifacts.apply(self.root, self.manifest)

    def test_interrupt_after_unlink_is_resumable(self):
        self.plan()
        real_inventory = artifacts.inventory
        calls = 0

        def interrupt(root, names):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise KeyboardInterrupt()
            return real_inventory(root, names)

        with patch.object(artifacts, "inventory", side_effect=interrupt):
            with self.assertRaises(KeyboardInterrupt):
                artifacts.apply(self.root, self.manifest)
        self.assertFalse((self.cache / "object").exists())
        self.assertEqual(artifacts.apply(self.root, self.manifest)["deleted_files"], 1)

    def test_symlink_in_preview_and_changed_policy_are_rejected(self):
        (self.cache / "reference").symlink_to(self.protected)
        with self.assertRaises(ValueError):
            self.plan()
        (self.cache / "reference").unlink()
        self.plan()
        with (self.root / artifacts.POLICY).open("a") as stream:
            stream.write("\n")
        with self.assertRaises(ValueError):
            artifacts.apply(self.root, self.manifest)

    def test_active_builder_and_open_candidate_are_rejected(self):
        self.guard.stop()

        def output(root, *args):
            return "987654 xcodebuild\n" if args[0] == "ps" else ""

        with patch.object(artifacts, "command", side_effect=output):
            with self.assertRaisesRegex(ValueError, "Active build"):
                artifacts.guard(self.root, [self.name])
        with (
            patch.object(artifacts, "command", return_value=""),
            patch.object(
                artifacts.subprocess,
                "run",
                return_value=type(
                    "Result",
                    (),
                    {"returncode": 0, "stderr": "", "stdout": f"p123\nn{self.cache}/object\n"},
                )(),
            ),
        ):
            with self.assertRaisesRegex(ValueError, "process is using"):
                artifacts.guard(self.root, [self.name])


if __name__ == "__main__":
    unittest.main()
