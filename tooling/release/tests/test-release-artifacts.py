"""Release archives, packages and debug evidence must never replace older runs."""

import datetime
import importlib.util
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import release_artifacts as release  # noqa: E402


class ReleaseArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="reha release ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.value = ".local/releases/candidate"

    def reserve(self, **kwargs):
        with patch.object(release, "run", side_effect=[b"a" * 40 + b"\n", b""]):
            return release.reserve(self.value, root=self.root, **kwargs)

    def archive(self):
        source = self.reserve()
        app = source / "Products/Applications/Test.app"
        app.mkdir(parents=True)
        (source / "Info.plist").write_bytes(
            plistlib.dumps({"ApplicationProperties": {"ApplicationPath": "Applications/Test.app"}})
        )
        (app / "Info.plist").write_bytes(
            plistlib.dumps({"CFBundleExecutable": "Test", "CFBundleIdentifier": "at.test.app"})
        )
        (app / "Test").write_bytes(b"binary")
        dwarf = source / "dSYMs/Test.app.dSYM/Contents/Resources/DWARF/Test"
        dwarf.parent.mkdir(parents=True)
        dwarf.write_bytes(b"symbols")
        return source, app, dwarf

    def test_reservation_never_reuses_an_existing_or_failed_run(self):
        self.reserve()
        marker = self.root / self.value / "release-run.json"
        before = marker.read_bytes()
        with self.assertRaises(FileExistsError):
            self.reserve()
        self.assertEqual(marker.read_bytes(), before)

    def test_external_nested_and_symbolic_destinations_are_rejected(self):
        for name in [".local/builds/ios", ".local/releases/a/b", "../candidate"]:
            with self.assertRaises(ValueError):
                release.run_path(name, self.root)
        (self.root / ".local").mkdir()
        (self.root / ".local/releases").symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symbolic"):
            self.reserve()

    def test_explicit_historical_source_is_read_only_and_output_is_new(self):
        original = self.root / "previous.xcarchive"
        original.mkdir()
        evidence = original / "retained"
        evidence.write_bytes(b"prior release")
        self.assertEqual(self.reserve(archive=original), original)
        destination, source, record = release.load(self.value, self.root)
        self.assertEqual(source, original)
        self.assertEqual(record["source_kind"], "explicit-existing-archive")
        self.assertIsNone(record["archive_source_commit"])
        (destination / "Laßnitzhöhe.ipa").write_bytes(b"first package")
        with self.assertRaisesRegex(ValueError, "already exists"):
            release.load(self.value, self.root)
        self.assertEqual(evidence.read_bytes(), b"prior release")

    def test_package_publication_cannot_overwrite_existing_output(self):
        source, destination = self.root / "new", self.root / "existing"
        source.write_bytes(b"new package")
        destination.write_bytes(b"retained package")
        with self.assertRaises(FileExistsError):
            release.publish(source, destination)
        self.assertEqual(destination.read_bytes(), b"retained package")

    def test_symbols_require_matching_uuid_and_architecture_and_record_hashes(self):
        archive, app, dwarf = self.archive()
        identity = b"UUID: 11111111-1111-1111-1111-111111111111 (arm64) fixture\n"
        result = release.symbols(archive, app, runner=lambda *args: identity)
        self.assertEqual(result[0]["dwarf_sha256"], release.sha(dwarf))
        self.assertEqual(result[0]["binary_sha256"], release.sha(app / "Test"))
        for replacement in [
            identity.replace(b"arm64", b"x86_64"),
            identity.replace(b"1111", b"2222"),
        ]:
            with self.assertRaisesRegex(ValueError, "matching dSYM"):
                release.symbols(
                    archive,
                    app,
                    runner=lambda *args: replacement if args[-1] == str(dwarf) else identity,
                )
        dwarf.unlink()
        with self.assertRaisesRegex(ValueError, "matching dSYM"):
            release.symbols(archive, app, runner=lambda *args: identity)

    def test_archive_path_cannot_escape_products(self):
        archive, _, _ = self.archive()
        (archive / "Info.plist").write_bytes(
            plistlib.dumps({"ApplicationProperties": {"ApplicationPath": "../../elsewhere.app"}})
        )
        with self.assertRaisesRegex(ValueError, "escapes Products"):
            release.application(archive)

    def test_expired_profile_blocks_package_without_modifying_archive(self):
        _, app, _ = self.archive()
        spec = importlib.util.spec_from_file_location(
            "native_package_probe", release.ROOT / "tooling/release/package-native.py"
        )
        package = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(package)
        info = plistlib.loads((app / "Info.plist").read_bytes())
        info["CFBundleIdentifier"] = package.BUNDLE
        (app / "Info.plist").write_bytes(plistlib.dumps(info))
        entitlements = {
            "application-identifier": package.TEAM + "." + package.BUNDLE,
            "com.apple.developer.team-identifier": package.TEAM,
            "com.apple.security.application-groups": [package.GROUP, package.INTAKE_GROUP],
        }
        profile = {
            "Entitlements": entitlements,
            "TeamIdentifier": [package.TEAM],
            "ProvisionedDevices": ["synthetic-device"],
            "ExpirationDate": datetime.datetime(2000, 1, 1),
        }

        def invoke(*args):
            if args[0] == "ditto":
                shutil.copytree(args[1], args[2])
            elif args[0] == "security":
                return plistlib.dumps(profile)
            elif args[0] == "codesign" and "--entitlements" in args:
                return plistlib.dumps(entitlements)
            return b""

        stored = release.load(self.value, self.root)
        with (
            patch.object(release, "load", return_value=stored),
            patch.object(release, "symbols", return_value=[]),
            patch.object(package, "run", side_effect=invoke),
            patch.object(package, "verify", return_value={}),
        ):
            with self.assertRaisesRegex(ValueError, "expired"):
                package.package(self.value)
        self.assertEqual((app / "Test").read_bytes(), b"binary")
        self.assertFalse((stored[0] / "Laßnitzhöhe.ipa").exists())

    def test_archive_entry_rejects_missing_run_before_any_build(self):
        script = release.ROOT / "tooling/build/build-native.sh"
        import os

        result = subprocess.run(
            ["sh", str(script), "archive"],
            cwd=release.ROOT,
            env=dict(os.environ, RELEASE_RUN=""),
            text=True,
            capture_output=True,
            timeout=20,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Set RELEASE_RUN", result.stderr)
        self.assertNotIn("Compiling", result.stderr)


if __name__ == "__main__":
    unittest.main()
