"""Make recipes must find bootstrapped tools without inheriting a developer's PATH."""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class MakePathTests(unittest.TestCase):
    def test_direct_recipes_use_local_tools_from_a_clean_path(self):
        with tempfile.TemporaryDirectory(prefix="reha make fixture ") as directory:
            root = Path(directory)
            shutil.copyfile(ROOT / "Makefile", root / "Makefile")
            tools = root / ".tools/bin"
            tools.mkdir(parents=True)
            for name in ["uv", "cargo"]:
                tool = tools / name
                tool.write_text('#!/bin/sh\nprintf "%s\\n" "$0" "$@"\n')
                tool.chmod(0o755)
            # No model/download commands execute: both tools are fixture scripts.
            completed = subprocess.run(
                [shutil.which("make"), "prepare-listening", "RUN=fixture-output"],
                cwd=root,
                env=dict(os.environ, PATH="/usr/bin:/bin"),
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertIn(str(tools / "cargo"), completed.stdout)
            self.assertIn(str(tools / "uv"), completed.stdout)
            self.assertIn("ml/evaluation/speech/listening.py", completed.stdout)


if __name__ == "__main__":
    unittest.main()
