"""Packaging must reject missing, altered or unexpected privacy declarations."""

import plistlib
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tooling/release"))
from privacy import BUNDLE, SOURCES, verify_bundle  # noqa: E402


class PrivacyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.app = Path(self.temporary.name) / "Synthetic.app"
        self.components = {}
        for identifier, source in SOURCES.items():
            component = (
                self.app
                if identifier == BUNDLE
                else self.app / "PlugIns" / (source.split("/")[-1] + ".appex")
            )
            component.mkdir(parents=True)
            (component / "Info.plist").write_bytes(
                plistlib.dumps({"CFBundleIdentifier": identifier})
            )
            shutil.copyfile(
                ROOT / "apps/ios" / source / "PrivacyInfo.xcprivacy",
                component / "PrivacyInfo.xcprivacy",
            )
            self.components[identifier] = component

    def test_each_component_has_its_own_manifest(self):
        self.assertEqual(set(verify_bundle(self.app)), set(SOURCES))

    def test_missing_manifest_is_not_packaged(self):
        (self.components[BUNDLE + ".share"] / "PrivacyInfo.xcprivacy").unlink()
        with self.assertRaises(FileNotFoundError):
            verify_bundle(self.app)

    def test_tracking_or_missing_reason_cannot_silently_change(self):
        path = self.app / "PrivacyInfo.xcprivacy"
        original = plistlib.loads(path.read_bytes())
        for key, replacement in [("NSPrivacyTracking", True), ("NSPrivacyAccessedAPITypes", [])]:
            path.write_bytes(plistlib.dumps(dict(original, **{key: replacement})))
            with self.assertRaises(ValueError):
                verify_bundle(self.app)

    def test_extra_or_missing_extension_is_not_packaged(self):
        extra = self.app / "PlugIns/Unexpected.appex"
        shutil.copytree(self.components[BUNDLE + ".share"], extra)
        with self.assertRaises(ValueError):
            verify_bundle(self.app)
        shutil.rmtree(extra)
        shutil.rmtree(self.components[BUNDLE + ".share"])
        with self.assertRaises(ValueError):
            verify_bundle(self.app)


if __name__ == "__main__":
    unittest.main()
