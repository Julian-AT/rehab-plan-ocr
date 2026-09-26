import hashlib
import importlib.util
import json
import os
import plistlib
import pwd
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
spec = importlib.util.spec_from_file_location(
    "archive_objects", Path(__file__).resolve().parents[1] / "archive_objects.py"
)
objects = importlib.util.module_from_spec(spec)
spec.loader.exec_module(objects)


@unittest.skipUnless(sys.platform == "darwin", "Requires macOS archive metadata APIs")
class ArchiveObjectTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.paths = []
        self.models = []
        self.runs = []
        for index, mode in enumerate([0o644, 0o640]):
            run = self.root / f".local/runs/fixture-{index}"
            path = run / objects.ARCHIVE
            path.parent.mkdir(parents=True)
            path.write_bytes(b"!<arch>\nunchanged synthetic archive payload")
            path.chmod(mode)
            os.utime(
                path, ns=(1_600_000_000_000_000_000 + index, 1_600_000_000_000_000_000 + index)
            )
            (run / "source.json").write_text(json.dumps({"head": "a" * 40}))
            (run / "product-locations.json").write_text(
                json.dumps({"products": "original independent producer"})
            )
            invocation = {
                "__xctestrun_metadata__": {"FormatVersion": 2},
                "TestConfigurations": [
                    {"TestTargets": [{"TestBundlePath": "__TESTROOT__/Runner.app/Tests.xctest"}]}
                ],
            }
            (run / "products/Termine.xctestrun").write_bytes(plistlib.dumps(invocation))
            model = path.parent / "App.app/model.onnx"
            model.parent.mkdir()
            model.write_bytes(b"protected packaged model")
            self.paths.append(path)
            self.models.append(model)
            self.runs.append(run)
        self.originals = self.root / ".local/originals/protected.bin"
        self.originals.parent.mkdir(parents=True)
        self.originals.write_bytes(b"protected original")
        self.review = self.root / ".local/maintenance/review.json"
        self.review.parent.mkdir(parents=True)
        group = {
            "sha256": hashlib.sha256(self.paths[0].read_bytes()).hexdigest(),
            "bytes": self.paths[0].stat().st_size,
            "paths": [
                {"path": str(path.relative_to(self.root)), "mode": path.stat().st_mode & 0o777}
                for path in self.paths
            ],
        }
        self.review.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "status": "read-only-inventory-no-files-changed",
                    "groups": [group],
                }
            )
        )
        self.manifest = self.root / ".local/maintenance/objects.json"
        self.guard = patch.object(objects, "guard")
        self.guard.start()
        self.addCleanup(self.guard.stop)

    def plan(self):
        return objects.plan(self.root, self.review, self.manifest)

    def test_actual_apfs_clone_preserves_metadata_history_and_independent_writes(self):
        os.chflags(self.paths[0], 0x8040)
        self.plan()
        before = [objects.identity(path) for path in self.paths]
        result = objects.apply(self.root, self.manifest)
        self.assertEqual(result["preserved_paths"], 2)

        self.assertEqual(result["deleted_paths"], [])
        self.assertEqual(objects.apply(self.root, self.manifest), result)
        self.assertEqual([objects.identity(path) for path in self.paths], before)
        canonical = next((self.root / ".local/objects/sha256").glob("*.a"))
        self.assertEqual(len({path.stat().st_ino for path in [*self.paths, canonical]}), 3)
        self.assertEqual(canonical.stat().st_mode & 0o777, 0o444)
        self.paths[0].write_bytes(b"independent subsequent write")
        later_inode = self.paths[0].stat().st_ino
        self.assertEqual(objects.apply(self.root, self.manifest), result)
        self.assertEqual(self.paths[0].stat().st_ino, later_inode)
        self.assertEqual(self.paths[0].read_bytes(), b"independent subsequent write")
        self.assertEqual(canonical.read_bytes(), self.paths[1].read_bytes())
        self.assertEqual(self.originals.read_bytes(), b"protected original")
        self.assertTrue(
            all(path.read_bytes() == b"protected packaged model" for path in self.models)
        )

    def test_a_real_compiler_archive_still_links_after_coalescing(self):
        implementation = self.root / "implementation.c"
        implementation.write_text("int retained_answer(void) { return 42; }\n")
        consumer = self.root / "consumer.c"
        consumer.write_text(
            "int retained_answer(void); int main(void) { return retained_answer() == 42 ? 0 : 1; }\n"
        )
        object_file = self.root / "implementation.o"
        subprocess.run(
            ["cc", "-c", str(implementation), "-o", str(object_file)],
            check=True,
            capture_output=True,
        )
        archive = self.root / "input.a"
        subprocess.run(
            ["ar", "rcs", str(archive), str(object_file)], check=True, capture_output=True
        )
        for path in self.paths:
            path.write_bytes(archive.read_bytes())
        value = json.loads(self.review.read_text())
        value["groups"][0].update(sha256=objects.sha(archive), bytes=archive.stat().st_size)
        self.review.write_text(json.dumps(value))
        self.plan()
        objects.apply(self.root, self.manifest)
        for index, path in enumerate(self.paths):
            executable = self.root / f"reader-{index}"
            subprocess.run(
                ["cc", str(consumer), str(path), "-o", str(executable)],
                check=True,
                capture_output=True,
            )
            subprocess.run([str(executable)], check=True, capture_output=True)

    def test_emitted_version_one_invocations_preserve_all_their_bytes(self):
        for run in self.runs:
            path = run / "products/Termine.xctestrun"
            value = plistlib.loads(path.read_bytes())
            targets = value.pop("TestConfigurations")[0]["TestTargets"]
            value["__xctestrun_metadata__"]["FormatVersion"] = 1
            value["TermineUITests"] = targets[0]
            path.write_bytes(plistlib.dumps(value))
        before = [(run / "products/Termine.xctestrun").read_bytes() for run in self.runs]
        self.plan()
        objects.apply(self.root, self.manifest)
        self.assertEqual(
            [(run / "products/Termine.xctestrun").read_bytes() for run in self.runs], before
        )

    def test_unknown_or_incomplete_invocation_formats_fail_closed(self):
        for value in [
            {"__xctestrun_metadata__": {"FormatVersion": 3}, "TestBundlePath": "a"},
            {"__xctestrun_metadata__": {"FormatVersion": True}, "Tests": {"TestBundlePath": "a"}},
            {"__xctestrun_metadata__": {"FormatVersion": 1}},
            {"__xctestrun_metadata__": {"FormatVersion": 1}, "Tests": {}},
            {"__xctestrun_metadata__": {"FormatVersion": 2}, "TestConfigurations": []},
            {
                "__xctestrun_metadata__": {"FormatVersion": 2},
                "TestConfigurations": [{"TestTargets": [{"TestBundlePath": "a"}, {}]}],
            },
        ]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                objects.test_targets(value)

    def test_archive_change_before_apply_rejects_all_replacements(self):
        self.plan()
        before = self.paths[0].stat().st_ino
        self.paths[1].write_bytes(b"!<arch>\nchanged")
        with self.assertRaises(ValueError):
            objects.apply(self.root, self.manifest)
        self.assertEqual(self.paths[0].stat().st_ino, before)

    def test_extended_attributes_are_refused_without_silent_metadata_loss(self):
        subprocess.run(
            [
                "/usr/bin/xattr",
                "-w",
                "at.reha.retention-fixture",
                "preserve-me",
                str(self.paths[0]),
            ],
            check=True,
            capture_output=True,
        )
        with self.assertRaisesRegex(ValueError, "Extended archive attributes"):
            self.plan()
        self.assertEqual(
            subprocess.check_output(
                ["/usr/bin/xattr", "-p", "at.reha.retention-fixture", str(self.paths[0])]
            ).strip(),
            b"preserve-me",
        )

    def test_acl_is_refused_without_changing_its_permissions(self):
        subprocess.run(
            [
                "/bin/chmod",
                "+a",
                f"user:{pwd.getpwuid(os.getuid()).pw_name}:allow:read",
                str(self.paths[0]),
            ],
            check=True,
            capture_output=True,
        )
        before = subprocess.check_output(["/bin/ls", "-lde", str(self.paths[0])])
        with self.assertRaisesRegex(ValueError, "Archive ACLs"):
            self.plan()
        self.assertEqual(subprocess.check_output(["/bin/ls", "-lde", str(self.paths[0])]), before)

    def test_changed_history_or_packaged_model_prevents_coalescing(self):
        log = self.runs[0] / "test.log"
        log.write_bytes(b"preserve completed test log")
        result = self.runs[0] / "result.xcresult/Data/data.bin"
        result.parent.mkdir(parents=True)
        result.write_bytes(b"preserve original result bytes")
        self.plan()
        for path in [self.runs[0] / "source.json", self.models[0], log, result]:
            original = path.read_bytes()
            path.write_bytes(b"changed")
            with self.assertRaises(ValueError):
                objects.apply(self.root, self.manifest)
            path.write_bytes(original)
        self.assertFalse(self.manifest.with_suffix(".receipt.json").exists())

    def test_symlink_or_original_path_is_never_eligible(self):
        values = json.loads(self.review.read_text())
        values["groups"][0]["paths"][0]["path"] = str(self.originals.relative_to(self.root))
        self.review.write_text(json.dumps(values))
        with self.assertRaises(ValueError):
            self.plan()
        self.assertFalse(
            objects.eligible(".local/runs/fixture/products/build-products/../backup.a")
        )

    def test_symlink_archive_and_missing_invocation_are_rejected(self):
        self.paths[1].unlink()
        self.paths[1].symlink_to(self.paths[0])
        with self.assertRaises(ValueError):
            self.plan()
        self.paths[1].unlink()
        shutil.copy2(self.paths[0], self.paths[1])
        self.paths[1].chmod(0o640)
        (self.runs[0] / "products/Termine.xctestrun").unlink()
        with self.assertRaises(ValueError):
            self.plan()

    def test_no_clone_support_keeps_originals_and_has_no_copy_fallback(self):
        self.plan()
        before = [objects.identity(path) for path in self.paths]
        with patch.object(objects, "clone", side_effect=OSError("Unsupported clone")):
            with self.assertRaises(OSError):
                objects.apply(self.root, self.manifest)
        self.assertEqual([objects.identity(path) for path in self.paths], before)

    def test_interrupted_replacement_can_resume_without_changing_old_evidence(self):
        self.plan()
        real = objects.replace_clone
        count = 0

        def interrupted(*args):
            nonlocal count
            real(*args)
            count += 1
            if count == 2:
                raise KeyboardInterrupt()

        with patch.object(objects, "replace_clone", side_effect=interrupted):
            with self.assertRaises(KeyboardInterrupt):
                objects.apply(self.root, self.manifest)
        self.assertFalse(self.manifest.with_suffix(".receipt.json").exists())
        result = objects.apply(self.root, self.manifest)
        self.assertEqual(result["preserved_paths"], 2)

    def test_a_concurrent_destination_change_survives_clone_preparation(self):
        self.plan()
        real = objects.clone

        def changed(source, destination):
            real(source, destination)
            if destination.parent == self.paths[0].parent:
                self.paths[0].write_bytes(b"!<arch>\nnew unreviewed producer output")

        with patch.object(objects, "clone", side_effect=changed):
            with self.assertRaisesRegex(ValueError, "Destination changed"):
                objects.apply(self.root, self.manifest)
        self.assertEqual(self.paths[0].read_bytes(), b"!<arch>\nnew unreviewed producer output")
        self.assertFalse(self.manifest.with_suffix(".receipt.json").exists())

    def test_change_between_precheck_and_clone_entry_is_not_overwritten(self):
        self.plan()
        real = objects.replace_clone

        def changed(source, destination, expected):
            if destination == self.paths[0]:
                destination.write_bytes(b"!<arch>\nnew output after the precheck")
            real(source, destination, expected)

        with patch.object(objects, "replace_clone", side_effect=changed):
            with self.assertRaisesRegex(ValueError, "reviewed identity"):
                objects.apply(self.root, self.manifest)
        self.assertEqual(self.paths[0].read_bytes(), b"!<arch>\nnew output after the precheck")
        self.assertFalse(self.manifest.with_suffix(".receipt.json").exists())

    def test_helper_change_invalidates_a_previously_reviewed_plan(self):
        self.plan()
        identities = objects.implementation_sources()
        identities["guards"] = "0" * 64
        with patch.object(objects, "implementation_sources", return_value=identities):
            with self.assertRaisesRegex(ValueError, "protocol"):
                objects.apply(self.root, self.manifest)
        self.assertFalse((self.root / ".local/objects").exists())

    def test_active_consumer_guard_prevents_any_replacement(self):
        self.plan()
        before = [path.stat().st_ino for path in self.paths]
        with patch.object(objects, "guard", side_effect=ValueError("Active consumer")):
            with self.assertRaisesRegex(ValueError, "Active consumer"):
                objects.apply(self.root, self.manifest)
        self.assertEqual([path.stat().st_ino for path in self.paths], before)
        self.assertFalse((self.root / ".local/objects").exists())

    def test_changed_canonical_object_cannot_replace_a_retained_archive(self):
        plan = self.plan()
        canonical = self.root / ".local/objects/sha256" / (plan["groups"][0]["sha256"] + ".a")
        canonical.parent.mkdir(parents=True)
        canonical.write_bytes(b"!<arch>\nchanged canonical object")
        before = [objects.identity(path) for path in self.paths]
        with self.assertRaisesRegex(ValueError, "canonical archive"):
            objects.apply(self.root, self.manifest)
        self.assertEqual([objects.identity(path) for path in self.paths], before)

    def test_tampered_review_or_plan_cannot_expand_the_selected_paths(self):
        original = self.plan()
        altered = json.loads(self.manifest.read_text())
        altered["groups"][0]["paths"].pop()
        self.manifest.write_text(json.dumps(altered))
        with self.assertRaises(ValueError):
            objects.apply(self.root, self.manifest)
        self.manifest.write_text(json.dumps(original))
        self.review.write_text(self.review.read_text() + " ")
        with self.assertRaises(ValueError):
            objects.apply(self.root, self.manifest)


if __name__ == "__main__":
    unittest.main()
