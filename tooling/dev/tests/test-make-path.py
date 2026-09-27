"""Make recipes must find bootstrapped tools without inheriting a developer's PATH."""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class MakePathTests(unittest.TestCase):
    def test_direct_recipes_use_local_tools_from_a_clean_path(self):
        with tempfile.TemporaryDirectory(prefix="reha make fixture ") as directory:
            root = Path(directory)
            shutil.copyfile(ROOT / "Makefile", root / "Makefile")
            shutil.copytree(ROOT / "tooling/make", root / "tooling/make")
            for name in [
                "tooling/dev/workspace.py",
                "config/storage/workspace.json",
                "config/toolchains/versions.json",
            ]:
                destination = root / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / name, destination)
            tools = root / ".local/tools/bin"
            tools.mkdir(parents=True)
            for name in ["uv", "cargo"]:
                tool = tools / name
                tool.write_text('#!/bin/sh\nprintf "%s\\n" "$0" "$@"\n')
                tool.chmod(0o755)
            bootstrap_bin = root / "bootstrap-bin"
            bootstrap_bin.mkdir()
            (bootstrap_bin / "python3").symlink_to(sys.executable)
            # No model/download commands execute: both tools are fixture scripts.
            completed = subprocess.run(
                [shutil.which("make"), "prepare-listening", "RUN=fixture-output"],
                cwd=root,
                env=dict(os.environ, PATH=f"{bootstrap_bin}:/usr/bin:/bin"),
                text=True,
                capture_output=True,
                check=False,
                timeout=60,
            )
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertIn(str(tools / "cargo"), completed.stdout)
            self.assertIn(str(tools / "uv"), completed.stdout)
            self.assertIn("ml/evaluation/speech/listening.py", completed.stdout)
            (root / "target").mkdir()
            (root / ".local/builds/rust").mkdir(parents=True)
            failed = subprocess.run(
                [shutil.which("make"), "prepare-listening", "RUN=fixture-output"],
                cwd=root,
                env=dict(os.environ, PATH=f"{bootstrap_bin}:/usr/bin:/bin", CARGO_TARGET_DIR=""),
                text=True,
                capture_output=True,
                timeout=60,
            )
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn("Workspace Cargo path is unresolved", failed.stderr)
            self.assertNotIn(str(tools / "cargo"), failed.stdout)


if __name__ == "__main__":
    unittest.main()
