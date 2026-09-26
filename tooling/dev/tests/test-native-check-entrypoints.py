"""Execute the test orchestrator with inert runners and validate its actual inputs."""

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import quality  # noqa: E402


class NativeEntrypointTests(unittest.TestCase):
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
