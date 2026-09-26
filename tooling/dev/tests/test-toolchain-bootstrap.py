"""Bootstrap must satisfy absolute-path consumers and every entry must pin Rust."""

import hashlib
import io
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import quality  # noqa: E402


class ToolchainBootstrapTests(unittest.TestCase):
    def test_matching_global_uv_does_not_satisfy_local_installation(self):
        with tempfile.TemporaryDirectory(prefix="reha tools ") as temporary:
            root = Path(temporary)
            global_bin = root / "global"
            global_bin.mkdir()
            uv = global_bin / "uv"
            uv.write_text(f'#!/bin/sh\necho "uv {quality.VERSIONS["uv"]}"\n')
            uv.chmod(0o755)
            with (
                patch.object(quality, "BIN", root / "local/bin"),
                patch.object(quality, "ENV", dict(os.environ, PATH=str(global_bin))),
            ):
                self.assertTrue(quality.installed("uv"))
                self.assertFalse(quality.installed("uv", local=True))

    def test_bootstrap_downloads_missing_local_tool_even_if_global_tool_matches(self):
        checked = []

        def installed(name, *, local=False):
            checked.append((name, local))
            return not local

        def run(*command, **_kwargs):
            self.assertEqual(command[0], "curl")
            raise RuntimeError("fixture download boundary")

        with (
            tempfile.TemporaryDirectory() as temporary,
            patch.object(quality, "BIN", Path(temporary) / "bin"),
            patch.object(quality, "space"),
            patch.object(quality.workspace, "prepare"),
            patch.object(quality, "installed", side_effect=installed),
            patch.object(quality, "run", side_effect=run),
        ):
            with self.assertRaisesRegex(RuntimeError, "fixture download boundary"):
                quality.bootstrap()
        self.assertEqual(checked, [("uv", True)])

    def test_doctor_rejects_divergent_rust_pin_before_running_tools(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "rust-toolchain.toml").write_text('[toolchain]\nchannel="0.0.0"\n')
            with patch.object(quality, "ROOT", root), patch.object(quality, "run") as run:
                with self.assertRaisesRegex(RuntimeError, "toolchain file differs"):
                    quality.doctor(portable=True)
                run.assert_not_called()


class ToolInstallationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="reha tools ")
        self.addCleanup(self.temporary.cleanup)
        self.prefix = Path(self.temporary.name)
        self.binary = self.prefix / "bin/uv"
        self.binary.parent.mkdir()
        self.data = f'#!/bin/sh\necho "uv {quality.VERSIONS["uv"]}"\n'.encode()
        packed = io.BytesIO()
        with tarfile.open(fileobj=packed, mode="w:gz") as archive:
            member = tarfile.TarInfo("release/uv")
            member.size = len(self.data)
            archive.addfile(member, io.BytesIO(self.data))
        self.archive = packed.getvalue()
        self.artifact = {
            "url": "https://fixture.invalid/uv.tar.gz",
            "sha256": hashlib.sha256(self.archive).hexdigest(),
        }
        for patcher in (
            patch.object(quality, "BIN", self.binary.parent),
            patch.object(quality, "tool_artifact", return_value=self.artifact),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def cached_archive(self):
        cache = self.prefix / "downloads" / self.artifact["sha256"]
        cache.parent.mkdir(exist_ok=True)
        cache.write_bytes(self.archive)
        return cache

    def legacy_binary(self, data=None):
        self.binary.write_bytes(self.data if data is None else data)
        self.binary.chmod(0o755)

    def test_version_correct_legacy_binary_is_not_executed_without_provenance(self):
        self.legacy_binary()
        with patch.object(quality, "run") as run:
            self.assertFalse(quality.installed("uv", local=True))
            run.assert_not_called()

    def test_legacy_migration_compares_pinned_archive_and_keeps_binary_timestamp(self):
        self.legacy_binary()
        self.cached_archive()
        before = self.binary.stat().st_mtime_ns
        with patch.object(quality, "run") as run:
            quality.install_tool("uv")
            run.assert_not_called()
        self.assertEqual(self.binary.stat().st_mtime_ns, before)
        self.assertEqual(self.binary.read_bytes(), self.data)
        self.assertTrue(quality.installed("uv", local=True))

    def test_corrupt_binary_with_same_version_is_repaired_offline(self):
        self.cached_archive()
        quality.install_tool("uv")
        self.legacy_binary(self.data + b"# different bytes, same reported version\n")
        with patch.object(quality, "run") as run:
            self.assertFalse(quality.installed("uv", local=True))
            quality.install_tool("uv")
            run.assert_not_called()
        self.assertEqual(self.binary.read_bytes(), self.data)
        self.assertTrue(quality.installed("uv", local=True))

    def test_legacy_path_alias_still_requires_the_local_receipt(self):
        self.cached_archive()
        quality.install_tool("uv")
        alias = self.prefix / "legacy-bin"
        alias.symlink_to(self.binary.parent, target_is_directory=True)
        with patch.object(quality.shutil, "which", return_value=str(alias / "uv")):
            self.assertTrue(quality.installed("uv"))
            self.legacy_binary(self.data + b"# modified through compatibility path\n")
            with patch.object(quality, "run") as run:
                self.assertFalse(quality.installed("uv"))
                run.assert_not_called()

    def test_unchanged_offline_bootstrap_preserves_receipt_and_archive(self):
        cache = self.cached_archive()
        quality.install_tool("uv")
        receipt = self.prefix / "receipts/uv.json"
        before = {
            path: (path.read_bytes(), path.stat().st_mtime_ns)
            for path in [self.binary, receipt, cache]
        }
        original_installed = quality.installed
        with (
            patch.object(
                quality,
                "installed",
                side_effect=lambda tool, **kwargs: (
                    original_installed(tool, **kwargs) if tool == "uv" else True
                ),
            ),
            patch.object(quality, "space"),
            patch.object(quality.workspace, "prepare"),
            patch.object(
                quality,
                "run",
                side_effect=lambda *command, **kwargs: (
                    quality.VERSIONS["uv"]
                    if command[0] == str(self.binary)
                    else quality.VERSIONS["rust"]
                ),
            ),
            patch.object(quality, "install_tool") as install,
        ):
            quality.bootstrap()
            install.assert_not_called()
        self.assertTrue(quality.installed("uv", local=True))
        self.assertEqual(
            {path: (path.read_bytes(), path.stat().st_mtime_ns) for path in before}, before
        )

    def test_new_pin_or_malformed_receipt_rejects_existing_installation(self):
        self.cached_archive()
        quality.install_tool("uv")
        with patch.object(
            quality, "tool_artifact", return_value=self.artifact | {"sha256": "changed"}
        ):
            self.assertFalse(quality.installed("uv", local=True))
        receipt = self.prefix / "receipts/uv.json"
        for value in [None, [], {}, {"schema_version": 2}]:
            with self.subTest(receipt=value):
                receipt.write_text(json.dumps(value))
                self.assertFalse(quality.installed("uv", local=True))

    def test_offline_bootstrap_repairs_permissions_without_archive_or_receipt_rewrite(self):
        cache = self.cached_archive()
        quality.install_tool("uv")
        cache.unlink()
        self.binary.chmod(0o644)
        receipt = self.prefix / "receipts/uv.json"
        before = {
            path: (path.read_bytes(), path.stat().st_mtime_ns, path.stat().st_ino)
            for path in [self.binary, receipt]
        }
        self.assertFalse(quality.installed("uv", local=True))
        original_installed, original_run = quality.installed, quality.run

        def run(*command, **kwargs):
            if command[0] == str(self.binary):
                return original_run(*command, **kwargs)
            self.assertIn(command[0], ["uv", "rustc", "rustup"])
            return quality.VERSIONS["rust"]

        with (
            patch.object(
                quality,
                "installed",
                side_effect=lambda tool, **kwargs: (
                    original_installed(tool, **kwargs) if tool == "uv" else True
                ),
            ),
            patch.object(quality, "space"),
            patch.object(quality.workspace, "prepare"),
            patch.object(quality, "run", side_effect=run),
            patch.object(quality, "install_tool") as install,
        ):
            quality.bootstrap()
            install.assert_not_called()
        self.assertTrue(quality.installed("uv", local=True))
        self.assertEqual(self.binary.stat().st_mode & 0o777, 0o755)
        self.assertFalse(cache.exists())
        self.assertEqual(
            {
                path: (path.read_bytes(), path.stat().st_mtime_ns, path.stat().st_ino)
                for path in before
            },
            before,
        )

    def test_version_start_oserror_is_not_installed_but_command_failure_is_preserved(self):
        self.cached_archive()
        quality.install_tool("uv")
        with patch.object(quality, "run", side_effect=OSError("invalid executable")):
            self.assertFalse(quality.installed("uv", local=True))
        with patch.object(
            quality, "run", side_effect=subprocess.CalledProcessError(2, ["uv", "--version"])
        ):
            with self.assertRaises(subprocess.CalledProcessError):
                quality.installed("uv", local=True)

    def test_global_tool_permissions_are_not_repaired_by_version_check(self):
        global_binary = self.prefix / "global-uv"
        global_binary.write_bytes(self.data)
        global_binary.chmod(0o644)
        with patch.object(quality.shutil, "which", return_value=str(global_binary)):
            self.assertFalse(quality.installed("uv"))
        self.assertEqual(global_binary.stat().st_mode & 0o777, 0o644)

    def test_install_replaces_tool_symlink_without_changing_external_permissions(self):
        self.cached_archive()
        external = self.prefix / "external-uv"
        external.write_bytes(self.data)
        external.chmod(0o644)
        self.binary.symlink_to(external)
        with patch.object(quality, "run") as run:
            quality.install_tool("uv")
            run.assert_not_called()
        self.assertFalse(self.binary.is_symlink())
        self.assertEqual(external.stat().st_mode & 0o777, 0o644)
        self.assertEqual(external.read_bytes(), self.data)
        self.assertTrue(quality.installed("uv", local=True))

    def test_corrupt_download_cannot_legitimize_legacy_binary(self):
        self.legacy_binary(self.data + b"# unknown provenance\n")
        before = self.binary.read_bytes()
        cache = self.cached_archive()
        cache.write_bytes(b"corrupt archive")

        def download(*command, **kwargs):
            self.assertEqual(command[0], "curl")
            Path(command[-1]).write_bytes(b"wrong download")

        with patch.object(quality, "run", side_effect=download):
            with self.assertRaisesRegex(RuntimeError, "Prüfsumme"):
                quality.install_tool("uv")
        self.assertEqual(self.binary.read_bytes(), before)
        self.assertFalse((self.prefix / "receipts/uv.json").exists())
        self.assertEqual(cache.read_bytes(), b"corrupt archive")

    def test_zip_and_standalone_tool_restore_from_verified_offline_cache(self):
        for suffix in [".zip", ""]:
            with self.subTest(suffix=suffix):
                if suffix:
                    packed = io.BytesIO()
                    with zipfile.ZipFile(packed, "w") as archive:
                        archive.writestr("release/uv", self.data)
                    self.archive = packed.getvalue()
                else:
                    self.archive = self.data
                self.artifact.update(
                    url="https://fixture.invalid/uv" + suffix,
                    sha256=hashlib.sha256(self.archive).hexdigest(),
                )
                self.cached_archive()
                self.binary.unlink(missing_ok=True)
                with patch.object(quality, "run") as run:
                    quality.install_tool("uv")
                    run.assert_not_called()
                self.assertTrue(quality.installed("uv", local=True))


if __name__ == "__main__":
    unittest.main()
