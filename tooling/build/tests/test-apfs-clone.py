"""Tiny real APFS fixtures; no models, compiler, simulator or ordinary-copy success."""

import ctypes
import errno
import hashlib
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from ml.evaluation.device import simulator  # noqa: E402
from tooling.utils import apfs_clone as copying  # noqa: E402
from tooling.utils import xcresult  # noqa: E402


@unittest.skipUnless(sys.platform == "darwin", "Real strict APFS contract requires Darwin")
class CloneTests(unittest.TestCase):
    def setUp(self):
        area = ROOT / ".local/tmp"
        area.mkdir(parents=True, exist_ok=True)
        if shutil.disk_usage(area).free < 20 * 1024**3:
            self.skipTest("Keep the predeclared 20-GiB reserve")
        self.temp = tempfile.TemporaryDirectory(dir=area, prefix="apfs-clone-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "Source.app"
        self.source.mkdir()
        self.file = self.source / "binary"
        self.file.write_bytes(bytes(range(256)) * 64)
        self.file.chmod(0o750)
        self.destination = self.root / "Copy.app"
        self.lib = copying.library()

    def test_real_clone_preserves_metadata_and_has_independent_writable_inode(self):
        subprocess.run(
            ["/usr/bin/xattr", "-w", "org.reha.fixture", "original", str(self.file)],
            check=True,
            timeout=10,
        )
        subprocess.run(
            ["/bin/chmod", "+a", "everyone allow read", str(self.file)], check=True, timeout=10
        )
        subprocess.run(
            ["/usr/bin/xattr", "-w", "org.reha.directory", "original", str(self.source)],
            check=True,
            timeout=10,
        )
        subprocess.run(
            ["/bin/chmod", "+a", "everyone allow list,search", str(self.source)],
            check=True,
            timeout=10,
        )
        os.chflags(self.file, stat.UF_HIDDEN)
        os.utime(self.file, ns=(1_700_000_000_000_000_000, 1_700_000_000_111_111_111))
        before = copying.snapshot(self.lib, self.source, True)
        result = copying.clone(self.source, self.destination)
        self.assertEqual(result, {"method": "darwin-copyfile-clone-force", "files": 1})
        copied = self.destination / "binary"
        self.assertNotEqual(copied.stat().st_ino, self.file.stat().st_ino)
        self.assertEqual(copied.stat().st_nlink, 1)
        self.assertEqual(copying.acl_text(self.lib, copied), copying.acl_text(self.lib, self.file))
        self.assertIsNotNone(copying.acl_text(self.lib, copied))
        copied.write_bytes(b"edited copy")
        subprocess.run(["/usr/bin/xattr", "-cr", str(self.destination)], check=True, timeout=10)
        self.assertEqual(copying.snapshot(self.lib, self.source, True), before)

    def test_internal_framework_links_preserved_without_following(self):
        framework = self.source / "Framework.framework"
        version = framework / "Versions/A"
        version.mkdir(parents=True)
        (version / "Framework").write_bytes(b"fixture framework")
        (framework / "Versions/Current").symlink_to("A")
        (framework / "Framework").symlink_to("Versions/Current/Framework")
        copying.clone(self.source, self.destination)
        copied = self.destination / "Framework.framework/Framework"
        self.assertTrue(copied.is_symlink())
        self.assertEqual(os.readlink(copied), "Versions/Current/Framework")
        self.assertEqual(copied.read_bytes(), b"fixture framework")

    def test_escaping_absolute_dangling_and_disallowed_links_stop_before_destination(self):
        outside = self.root / "outside"
        outside.write_text("unrelated original")
        for target in ["../outside", str(self.file), "missing", "link"]:
            link = self.source / "link"
            link.symlink_to(target)
            with self.subTest(target=target), self.assertRaises((ValueError, OSError)):
                copying.clone(self.source, self.destination)
            self.assertFalse(self.destination.exists())
            link.unlink()
        link.symlink_to("binary")
        with self.assertRaises(ValueError):
            copying.clone(self.source, self.destination, allow_symlinks=False)
        self.assertFalse(self.destination.exists())
        self.assertEqual(outside.read_text(), "unrelated original")

    def test_foreign_existing_symlink_nested_and_hardlink_destinations_untouched(self):
        foreign = self.root / "foreign"
        foreign.write_text("protected")
        for destination in [self.source, self.source / "nested", foreign]:
            with self.subTest(destination=destination), self.assertRaises(ValueError):
                copying.clone(self.source, destination)
        self.destination.symlink_to(foreign)
        with self.assertRaises(ValueError):
            copying.clone(self.source, self.destination)
        self.assertTrue(self.destination.is_symlink())
        self.assertEqual(foreign.read_text(), "protected")
        self.destination.unlink()
        os.link(self.file, self.source / "hardlink")
        with self.assertRaisesRegex(ValueError, "hardlinked"):
            copying.clone(self.source, self.destination)
        self.assertFalse(self.destination.exists())

    def test_same_volume_exact_apfs_and_darwin_required(self):
        for platform in ["linux", "win32"]:
            with patch.object(copying.sys, "platform", platform), self.assertRaises(ValueError):
                copying.clone(self.source, self.destination)
        with patch.object(copying, "filesystem", return_value="hfs"), self.assertRaises(ValueError):
            copying.clone(self.source, self.destination)
        original_stat = Path.stat

        def different_device(path, *args, **kwargs):
            value = original_stat(path, *args, **kwargs)
            if path == self.root:
                return type("DifferentVolume", (), {"st_dev": value.st_dev + 1})()
            return value

        with (
            patch.object(Path, "stat", different_device),
            self.assertRaisesRegex(ValueError, "same volume"),
        ):
            copying.clone(self.source, self.destination)
        self.assertFalse(self.destination.exists())

    def test_kernel_clone_failure_never_runs_ordinary_copy(self):
        class Fail:
            def __getattr__(self, name):
                return getattr(self.lib, name)

            def copyfile(self, source, destination, state, flags):
                self.flags = flags
                ctypes.set_errno(errno.ENOTSUP)
                return -1

        fake = Fail()
        fake.lib = self.lib
        with self.assertRaises(OSError):
            copying.strict_file(fake, self.file, self.destination)
        self.assertTrue(fake.flags & copying.CLONE_FORCE)
        self.assertFalse(self.destination.exists())

    def test_full_copy_cannot_claim_success_without_kernel_clone_receipt(self):
        class Fallback:
            def __getattr__(self, name):
                return getattr(self.lib, name)

            def copyfile(self, source, destination, state, flags):
                # Intentionally simulate the cp -c bug with a real tiny full copy.
                return self.lib.copyfile(
                    source, destination, state, 15 | (1 << 17) | copying.NOFOLLOW
                )

        fake = Fallback()
        fake.lib = self.lib
        with self.assertRaisesRegex(ValueError, "did not attest"):
            copying.strict_file(fake, self.file, self.destination)
        self.assertEqual(self.destination.read_bytes(), self.file.read_bytes())
        self.assertEqual(self.file.stat().st_nlink, 1)

    def test_destination_created_after_precheck_is_not_overwritten(self):
        original = copying.strict_file

        def compete(lib, source, destination):
            destination.write_bytes(b"foreign writer")
            original(lib, source, destination)

        with patch.object(copying, "strict_file", compete), self.assertRaises(OSError):
            copying.clone(self.file, self.destination)
        self.assertEqual(self.destination.read_bytes(), b"foreign writer")
        self.assertNotEqual(self.file.read_bytes(), b"foreign writer")

    def test_cloned_metadata_mismatch_fails_without_mutating_source(self):
        before = copying.snapshot(self.lib, self.source, True)
        original = copying.strict_file

        def corrupt_mode(lib, source, destination):
            original(lib, source, destination)
            destination.chmod(0o600)

        with (
            patch.object(copying, "strict_file", corrupt_mode),
            self.assertRaisesRegex(ValueError, "metadata"),
        ):
            copying.clone(self.source, self.destination)
        self.assertEqual(copying.snapshot(self.lib, self.source, True), before)

    def test_registered_hash_or_size_replacement_stops_before_copy(self):
        digest = hashlib.sha256(self.file.read_bytes()).hexdigest()
        for kwargs in [
            {"expected_sha256": "0" * 64},
            {"expected_bytes": self.file.stat().st_size + 1},
        ]:
            with self.assertRaises(ValueError):
                copying.clone(self.file, self.destination, **kwargs)
            self.assertFalse(self.destination.exists())
        copying.clone(
            self.file,
            self.destination,
            expected_sha256=digest,
            expected_bytes=self.file.stat().st_size,
        )

    def test_previously_verified_app_resource_cannot_change_before_staging(self):
        digest = hashlib.sha256(self.file.read_bytes()).hexdigest()
        self.file.write_bytes(b"replaced before staging")
        calls = []
        with self.assertRaisesRegex(ValueError, "pinned resource"):
            simulator.signed_copy(
                self.source, self.destination, calls.append, expected_files={"binary": digest}
            )
        self.assertFalse(self.destination.exists())
        self.assertEqual(calls, [])

    def test_source_change_between_check_and_kernel_clone_is_rejected(self):
        original = copying.strict_file

        def mutate(lib, source, destination):
            source.write_bytes(b"changed between check and clone")
            original(lib, source, destination)

        with (
            patch.object(copying, "strict_file", mutate),
            self.assertRaisesRegex(ValueError, "Source changed"),
        ):
            copying.clone(self.source, self.destination)
        self.assertTrue(self.destination.is_dir())  # Unqualified failure evidence is retained.

    def test_source_replacement_with_external_link_cannot_produce_success(self):
        original = copying.strict_file
        outside = self.root / "outside"
        outside.write_bytes(b"unrelated")

        def mutate(lib, source, destination):
            source.unlink()
            source.symlink_to(outside)
            original(lib, source, destination)

        with patch.object(copying, "strict_file", mutate), self.assertRaises((ValueError, OSError)):
            copying.clone(self.source, self.destination)
        self.assertEqual(outside.read_bytes(), b"unrelated")

    def test_signed_copy_can_clear_xattrs_and_write_only_its_copy(self):
        before = copying.snapshot(self.lib, self.source, True)
        commands = []

        def run(command):
            commands.append(command)
            if command[0] == "xattr":
                subprocess.run(["/usr/bin/xattr", *command[1:]], check=True, timeout=10)
            if command[0] == "codesign" and Path(command[-1]) == self.destination:
                (self.destination / "binary").write_bytes(b"synthetic signed bytes")

        simulator.signed_copy(self.source, self.destination, run)
        self.assertEqual(len([c for c in commands if c[0] == "codesign"]), 4)
        self.assertEqual(copying.snapshot(self.lib, self.source, True), before)
        self.assertEqual((self.destination / "binary").read_bytes(), b"synthetic signed bytes")
        with patch.object(simulator, "clone", side_effect=OSError("unsupported clone")):
            commands.clear()
            with self.assertRaises(OSError):
                simulator.signed_copy(self.source, self.root / "failed.app", run)
            self.assertEqual(commands, [])

    def test_result_working_copy_preserves_original_and_rejects_symlinks(self):
        before = copying.snapshot(self.lib, self.source, True)
        with xcresult.preserved_result(self.source) as (working, inventory):
            self.assertTrue(working.is_relative_to(ROOT / ".local"))
            (working / "index").write_bytes(b"temporary generated result index")
            self.assertEqual(inventory["binary"]["bytes"], self.file.stat().st_size)
        self.assertFalse(working.exists())
        self.assertEqual(copying.snapshot(self.lib, self.source, True), before)
        (self.source / "link").symlink_to("binary")
        with self.assertRaises(ValueError):
            with xcresult.preserved_result(self.source):
                self.fail("Evidence symlink accepted")


if __name__ == "__main__":
    unittest.main()
