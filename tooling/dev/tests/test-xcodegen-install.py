"""A version-correct XcodeGen binary without presets is not a complete installation."""

import io
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import quality  # noqa: E402


def archive(*, omit=None, extra=None):
    data = io.BytesIO()
    with zipfile.ZipFile(data, "w") as output:
        output.writestr("xcodegen/LICENSE", "Synthetic test license")
        for name in quality.XCODEGEN_PRESETS - {omit}:
            output.writestr(
                "xcodegen/share/xcodegen/SettingPresets/" + name, "PRODUCT_NAME: $(TARGET_NAME)\n"
            )
        if extra:
            output.writestr("xcodegen/share/xcodegen/" + extra, "fixture")
    data.seek(0)
    return zipfile.ZipFile(data)


class XcodeGenInstallTests(unittest.TestCase):
    @unittest.skipUnless(sys.platform == "darwin", "Actual Xcode project settings require macOS")
    def test_installed_generator_produces_distinct_extension_products(self):
        binary = shutil.which("xcodegen", path=quality.ENV["PATH"])
        self.assertIsNotNone(binary)
        with tempfile.TemporaryDirectory(prefix="reha-xcodegen-fixture-") as directory:
            root = Path(directory)
            spec = root / "project.yml"
            spec.write_text(
                "name: Fixture\ntargets:\n"
                "  First:\n    type: app-extension\n    platform: iOS\n"
                "  Second:\n    type: app-extension\n    platform: iOS\n"
            )
            generated = subprocess.run(
                [binary, "generate", "--spec", str(spec)],
                cwd=root,
                env=quality.ENV,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertNotIn('No "', generated.stdout + generated.stderr)
            completed = subprocess.run(
                [
                    "xcodebuild",
                    "-project",
                    str(root / "Fixture.xcodeproj"),
                    "-alltargets",
                    "-configuration",
                    "Release",
                    "-showBuildSettings",
                    "-json",
                ],
                cwd=root,
                env=quality.ENV,
                check=True,
                capture_output=True,
                text=True,
            )
            settings = json.loads(completed.stdout)
            self.assertEqual(
                {entry["buildSettings"]["FULL_PRODUCT_NAME"] for entry in settings},
                {"First.appex", "Second.appex"},
            )

    def test_missing_and_modified_resources_require_repair(self):
        with tempfile.TemporaryDirectory() as temporary:
            prefix = Path(temporary)
            binary = prefix / "bin/xcodegen"
            binary.parent.mkdir()
            binary.write_text("fixture executable")
            alias = prefix / "compat-bin"
            alias.symlink_to(binary.parent, target_is_directory=True)
            digest = quality.LOCK["downloads"]["xcodegen"]["darwin-arm64"]["sha256"]
            with patch.object(quality, "BIN", binary.parent):
                self.assertFalse(quality.xcodegen_resources_ready(binary))
                with archive() as zipped:
                    quality.install_xcodegen_resources(zipped, digest, prefix)
                self.assertTrue(quality.xcodegen_resources_ready(binary))
                self.assertTrue(quality.xcodegen_resources_ready(alias / "xcodegen"))
                base = prefix / "share/xcodegen/SettingPresets/base.yml"
                base.write_text("changed")
                self.assertFalse(quality.xcodegen_resources_ready(binary))
                self.assertFalse(quality.xcodegen_resources_ready(alias / "xcodegen"))
                with archive() as zipped:
                    quality.install_xcodegen_resources(zipped, digest, prefix)
                self.assertTrue(quality.xcodegen_resources_ready(binary))
                self.assertEqual(
                    (prefix / "share/xcodegen/LICENSE").read_text(), "Synthetic test license"
                )

    def test_incomplete_or_escaping_archive_never_replaces_existing_presets(self):
        for kwargs in (
            dict(omit="base.yml"),
            dict(extra="../../escape"),
            dict(extra="unexpected.txt"),
        ):
            with self.subTest(kwargs=kwargs), tempfile.TemporaryDirectory() as temporary:
                prefix = Path(temporary)
                sentinel = prefix / "share/xcodegen/retained"
                sentinel.parent.mkdir(parents=True)
                sentinel.write_text("existing")
                with archive(**kwargs) as zipped, self.assertRaises(ValueError):
                    quality.install_xcodegen_resources(zipped, "fixture-digest", prefix)
                self.assertEqual(sentinel.read_text(), "existing")

    def test_version_alone_does_not_satisfy_doctor(self):
        with tempfile.TemporaryDirectory() as temporary:
            binary = Path(temporary) / "bin/xcodegen"
            with (
                patch.object(quality.shutil, "which", return_value=str(binary)),
                patch.object(
                    quality, "run", return_value=f"Version: {quality.VERSIONS['xcodegen']}"
                ),
            ):
                self.assertFalse(quality.installed("xcodegen"))


if __name__ == "__main__":
    unittest.main()
