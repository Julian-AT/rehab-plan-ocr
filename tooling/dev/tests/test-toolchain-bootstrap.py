"""Bootstrap must satisfy absolute-path consumers and every entry must pin Rust."""

import os
import sys
import tempfile
import unittest
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


if __name__ == "__main__":
    unittest.main()
