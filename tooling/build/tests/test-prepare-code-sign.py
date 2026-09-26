"""Signing metadata cleanup stays on generated app/extension products."""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "prepare-code-sign.sh"


@unittest.skipUnless(sys.platform == "darwin", "Apple extended attributes")
class SigningMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / "Fixture.app"
        self.app.mkdir()
        self.binary = self.app / "Executable"
        self.binary.write_bytes(b"unchanged compiled content")
        subprocess.run(
            ["xattr", "-w", "org.reha.fixture", "metadata", str(self.binary)], check=True
        )

    def run_script(self, name="Fixture.app", allowed="YES"):
        return subprocess.run(
            ["sh", str(SCRIPT)],
            env=dict(
                os.environ,
                CODE_SIGNING_ALLOWED=allowed,
                TARGET_BUILD_DIR=str(self.root),
                FULL_PRODUCT_NAME=name,
            ),
            capture_output=True,
        )

    def attributes(self, path):
        return subprocess.check_output(["xattr", str(path)]).decode()

    def test_disabled_signing_does_not_change_metadata(self):
        self.assertEqual(self.run_script(allowed="NO").returncode, 0)
        self.assertIn("org.reha.fixture", self.attributes(self.binary))

    def test_cleanup_preserves_bytes_and_does_not_follow_resource_links(self):
        source = self.root / "source"
        source.write_bytes(b"external asset")
        subprocess.run(["xattr", "-w", "org.reha.fixture", "source", str(source)], check=True)
        (self.app / "link").symlink_to(source)
        (self.app / "dangling").symlink_to(self.root / "absent")
        self.assertEqual(self.run_script().returncode, 0)
        self.assertNotIn("org.reha.fixture", self.attributes(self.binary))
        self.assertEqual(self.binary.read_bytes(), b"unchanged compiled content")
        self.assertEqual(source.read_bytes(), b"external asset")
        self.assertIn("org.reha.fixture", self.attributes(source))

    def test_rejects_escape_and_symlink_products(self):
        self.assertNotEqual(self.run_script("../Fixture.app").returncode, 0)
        (self.root / "Alias.app").symlink_to(self.app)
        self.assertNotEqual(self.run_script("Alias.app").returncode, 0)
        self.assertNotEqual(self.run_script("Unrelated").returncode, 0)
        self.assertIn("org.reha.fixture", self.attributes(self.binary))


if __name__ == "__main__":
    unittest.main()
