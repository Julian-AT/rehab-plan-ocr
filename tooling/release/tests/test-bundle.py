"""Unsigned CI and signed packaging must reject inconsistent self-contained bundles."""

import hashlib
import json
import plistlib
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tooling/release"))
import bundle  # noqa: E402
import privacy  # noqa: E402
import runtime_inventory as inventory  # noqa: E402


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return json.dumps(value).encode()


class BundleTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / "source"
        self.app = Path(temporary.name) / "Synthetic.app"
        write(self.root / "Cargo.toml", b'[workspace.package]\nversion = "0.3.0"\n')
        self.components = {}
        for identifier, (name, executable, extension) in bundle.COMPONENTS.items():
            component = self.app / "PlugIns" / name if name else self.app
            info = {
                "CFBundleIdentifier": identifier,
                "CFBundleDisplayName": "Laßnitzhöhe",
                "CFBundleExecutable": executable,
                "CFBundleShortVersionString": "0.3.0",
                "CFBundleVersion": "123",
                "CFBundlePackageType": "XPC!" if extension else "APPL",
                "MinimumOSVersion": "26.0",
                "UIDeviceFamily": [1],
                "CFBundleSupportedPlatforms": ["iPhoneSimulator"],
            }
            if extension:
                info["NSExtension"] = {"NSExtensionPointIdentifier": extension}
            write(component / "Info.plist", plistlib.dumps(info))
            write(component / executable, b"Synthetic executable content, not a runnable binary")
            source = Path("apps/ios") / privacy.SOURCES[identifier] / "PrivacyInfo.xcprivacy"
            data = (ROOT / source).read_bytes()
            write(self.root / source, data)
            write(component / "PrivacyInfo.xcprivacy", data)
            self.components[identifier] = component
        for name in ["small"]:
            folder = name
            data = b"Synthetic model, no patient or trained data"
            digest = write(self.app / folder / "model.bin", data)
            lock = {
                "bundle_directory": folder,
                "files": [{"path": "model.bin", "sha256": digest, "bytes": len(data)}],
            }
            if name == "small":
                lock["dictionary_sha256"] = write(self.app / folder / "dictionary.json", b'["a"]')
            write(self.root / "ml/registry/runtime" / f"{name}.lock.json", encoded(lock))
            write(self.app / folder / "manifest.json", encoded(lock))
        digest = write(self.root / inventory.NOTICES / inventory.COMBINED, b"Synthetic notice")
        manifest_digest = write(
            self.root / inventory.NOTICES / "manifest.json", encoded({inventory.COMBINED: digest})
        )
        data = {
            "schema_version": 1,
            "target": inventory.TARGET,
            "source_inputs": {},
            "generated_notice_sha256": digest,
            "notice_manifest_sha256": manifest_digest,
            "rust_packages": [],
            "public_distribution_cleared": False,
        }
        write(self.root / inventory.INVENTORY, encoded(data))
        write(self.app / "runtime-inventory.json", encoded(data))
        shutil.copytree(self.root / inventory.NOTICES, self.app / "licenses")

    def verify(self, target="simulator"):
        return bundle.verify(self.app, target, self.root)

    def snapshot(self):
        return {
            str(p): (p.read_bytes(), p.stat().st_mtime_ns)
            for p in self.app.rglob("*")
            if p.is_file()
        }

    def test_valid_unsigned_bundle_is_checked_without_writes_or_release_claims(self):
        before = self.snapshot()
        report = self.verify()
        self.assertEqual(before, self.snapshot())
        self.assertEqual(len(report["components"]), 4)
        self.assertTrue(report["models"]["small"]["dictionary_verified"])
        self.assertFalse(report["signatures_verified"])
        self.assertEqual(report["physical_acceptance"], "pending")
        self.assertFalse(report["runtime_inventory"]["public_distribution_cleared"])
        self.assertEqual(set(report["models"]), {"small"})
        self.assertEqual(report["speech"]["bundled_model_files"], 0)

    def test_component_identity_version_platform_and_compatibility_are_required(self):
        for component in self.components.values():
            path = component / "Info.plist"
            original = path.read_bytes()
            for key, bad in [
                ("CFBundleIdentifier", "another.app"),
                ("CFBundleDisplayName", "Different branding"),
                ("CFBundleExecutable", "Missing"),
                ("CFBundleShortVersionString", "1.0.0"),
                ("CFBundlePackageType", "INVALID"),
                ("MinimumOSVersion", "26.1"),
                ("UIDeviceFamily", [1, 2]),
                ("CFBundleSupportedPlatforms", ["iPhoneOS"]),
                ("CFBundleVersion", "124"),
                ("REHAExperimentalAssistant", True),
            ]:
                with self.subTest(component=component.name, key=key):
                    path.write_bytes(plistlib.dumps(plistlib.loads(original) | {key: bad}))
                    with self.assertRaises(ValueError):
                        self.verify()
                    path.write_bytes(original)

    def test_missing_or_extra_components_and_wrong_extension_points_fail(self):
        folder = self.components[privacy.BUNDLE + ".share"]
        info = folder / "Info.plist"
        original = info.read_bytes()
        info.write_bytes(plistlib.dumps(plistlib.loads(original) | {"NSExtension": {}}))
        with self.assertRaisesRegex(ValueError, "extension point"):
            self.verify()
        info.write_bytes(original)
        extra = self.app / "PlugIns/Extra.appex"
        shutil.copytree(folder, extra)
        with self.assertRaisesRegex(ValueError, "unexpected app extension"):
            self.verify()
        shutil.rmtree(extra)
        shutil.rmtree(folder)
        with self.assertRaisesRegex(ValueError, "Missing"):
            self.verify()

    def test_wrong_target_and_missing_executable_fail(self):
        with self.assertRaisesRegex(ValueError, "CFBundleSupportedPlatforms"):
            self.verify("device")
        (self.app / "Termine").unlink()
        with self.assertRaisesRegex(ValueError, "Missing executable"):
            self.verify()

    def test_changed_or_missing_models_dictionary_manifests_and_notices_fail(self):
        for name in [
            "small/model.bin",
            "small/dictionary.json",
            "small/manifest.json",
            "runtime-inventory.json",
            "licenses/" + inventory.COMBINED,
            "PrivacyInfo.xcprivacy",
        ]:
            path = self.app / name
            original = path.read_bytes()
            with self.subTest(name=name):
                path.write_bytes(b"{}")
                with self.assertRaises((ValueError, plistlib.InvalidFileException)):
                    self.verify()
                path.unlink()
                with self.assertRaises((ValueError, FileNotFoundError)):
                    self.verify()
                path.write_bytes(original)

    def test_unexpected_model_payload_fails(self):
        write(self.app / "small/unreviewed.bin", b"Unexpected asset")
        with self.assertRaisesRegex(ValueError, "model files differ"):
            self.verify()

    def test_experimental_speech_resources_and_symbols_fail(self):
        for name in ["kokoro-german/model.onnx", "nested/espeak-ng-data/de_dict", "libucd.a"]:
            path = self.app / name
            write(path, b"Experimental speech artifact")
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "speech resources"):
                self.verify()
            path.unlink()
            # Empty excluded folders are rejected too.
            if path.parent != self.app:
                shutil.rmtree(self.app / Path(name).parts[0])
        for component in self.components.values():
            binary = (
                component
                / plistlib.loads((component / "Info.plist").read_bytes())["CFBundleExecutable"]
            )
            original = binary.read_bytes()
            # Cross the streaming boundary to catch split symbol records.
            binary.write_bytes(b"\0" * (1024 * 1024 - 5) + b"_espeak_Initialize\0")
            with self.assertRaisesRegex(ValueError, "eSpeak symbols"):
                self.verify()
            binary.write_bytes(original)

    def test_external_and_internal_symlinks_fail_even_for_matching_bytes(self):
        path = self.app / "small/model.bin"
        data = path.read_bytes()
        for destination in [self.root / "external.bin", self.app / "Termine"]:
            with self.subTest(destination=destination.name):
                write(destination, data)
                path.unlink()
                path.symlink_to(destination)
                with self.assertRaisesRegex(ValueError, "symbolic link"):
                    self.verify()
                path.unlink()
                path.write_bytes(data)

    def test_pinned_model_paths_cannot_escape_or_alias_existing_entries(self):
        manifest = self.app / "small/manifest.json"
        lock = self.root / "ml/registry/runtime/small.lock.json"
        original = json.loads(lock.read_text())
        for bad in ["../Termine", "/absolute", "manifest.json"]:
            with self.subTest(path=bad):
                changed = original | {"files": [original["files"][0] | {"path": bad}]}
                lock.write_bytes(encoded(changed))
                manifest.write_bytes(encoded(changed))
                with self.assertRaisesRegex(ValueError, "paths must be local"):
                    self.verify()


if __name__ == "__main__":
    unittest.main()
