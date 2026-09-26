"""Execute the test orchestrator with inert runners and validate its actual inputs."""

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import quality  # noqa: E402


class NativeEntrypointTests(unittest.TestCase):
    def test_low_space_stops_compiling_checks_before_tools_start(self):
        for command in [lambda: quality.tests(portable=True), lambda: quality.style(False, True)]:
            with (
                self.subTest(command=command),
                patch.object(
                    quality.shutil,
                    "disk_usage",
                    return_value=SimpleNamespace(free=24 * 1024**3 - 1),
                ),
                patch.object(quality, "doctor") as doctor,
                patch.object(quality, "run") as run,
                patch.object(quality, "tool_tests") as tools,
            ):
                with self.assertRaisesRegex(RuntimeError, "20 GiB Reserve"):
                    command()
                doctor.assert_not_called()
                run.assert_not_called()
                tools.assert_not_called()

    def test_exact_reserve_plus_compiler_budget_allows_checks(self):
        for command, expected in [
            (lambda: quality.tests(portable=True), "test"),
            (lambda: quality.style(False, True), "clippy"),
        ]:
            with (
                self.subTest(compiler=expected),
                patch.object(
                    quality.shutil, "disk_usage", return_value=SimpleNamespace(free=24 * 1024**3)
                ),
                patch.object(quality, "doctor"),
                patch.object(quality, "files", return_value=[]),
                patch.object(quality, "tool_tests"),
                patch.object(quality, "run") as run,
            ):
                command()
                self.assertTrue(any(c.args[:2] == ("cargo", expected) for c in run.call_args_list))

    def test_every_scheduled_native_probe_exists_and_is_scheduled_once(self):
        with (
            patch.object(quality, "APPLE", True),
            patch.object(quality, "doctor"),
            patch.object(quality, "space"),
            patch.object(quality, "tool_tests"),
            patch.object(quality, "run") as run,
        ):
            quality.tests(portable=False)
        scripts = [call.args[1] for call in run.call_args_list if call.args[0] == "sh"]
        self.assertGreater(len(scripts), 1)
        self.assertEqual(len(scripts), len(set(scripts)))
        for script in scripts:
            with self.subTest(script=script):
                self.assertTrue((quality.ROOT / script).is_file(), script)


if __name__ == "__main__":
    unittest.main()
