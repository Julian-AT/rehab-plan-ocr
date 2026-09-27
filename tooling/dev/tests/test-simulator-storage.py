"""A failed reserve check must prevent supported simulator workflows from starting."""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class SimulatorStorageTests(unittest.TestCase):
    def test_insufficient_headroom_stops_before_any_simulator_command(self):
        with tempfile.TemporaryDirectory(prefix="reha simulator reserve ") as directory:
            root = Path(directory)
            for name in [
                "Makefile",
                "tooling/dev/workspace.py",
                "config/storage/workspace.json",
                "config/toolchains/versions.json",
            ]:
                destination = root / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / name, destination)
            shutil.copytree(ROOT / "tooling/make", root / "tooling/make")
            (root / "tooling/dev/artifacts.py").write_text(
                'import sys\nassert sys.argv[1:] == ["space", "--peak-gib", "16"]\n'
                'print("reserve rejected", flush=True)\nraise SystemExit(23)\n'
            )
            (root / "tooling/dev/quality.py").write_text(
                'from pathlib import Path\nPath("workflow-started").touch()\n'
            )
            checks = root / "tooling/checks"
            checks.mkdir(parents=True)
            names = [
                "test-native-ui",
                "test-calendar-events",
                "test-visual-baseline",
                "test-reduced-motion",
                "test-audio-runtime",
            ]
            for name in names:
                (checks / f"{name}.sh").write_text("#!/bin/sh\ntouch workflow-started\n")
            bootstrap = root / "bootstrap-bin"
            bootstrap.mkdir()
            (bootstrap / "python3").symlink_to(sys.executable)
            for name in ["test-ios", *names]:
                with self.subTest(workflow=name):
                    result = subprocess.run(
                        [shutil.which("make"), name],
                        cwd=root,
                        env=dict(os.environ, PATH=f"{bootstrap}:/usr/bin:/bin"),
                        text=True,
                        capture_output=True,
                        timeout=30,
                    )
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("reserve rejected", result.stdout)
                    self.assertFalse((root / "workflow-started").exists())


if __name__ == "__main__":
    unittest.main()
