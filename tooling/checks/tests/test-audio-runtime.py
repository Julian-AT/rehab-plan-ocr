"""A successful simctl launch is insufficient to establish rendered audio."""

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "audio_runtime", Path(__file__).parents[1] / "audio-runtime.py"
)
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class CompletionTests(unittest.TestCase):
    def test_command_warnings_do_not_corrupt_machine_readable_output(self):
        result = runtime.command(
            sys.executable,
            "-c",
            "import sys; print('runtime warning', file=sys.stderr); print('device-identifier')",
        )
        self.assertEqual(result.stdout.strip(), "device-identifier")
        self.assertEqual(result.stderr.strip(), "runtime warning")

    def test_only_fresh_completed_render_is_successful(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "result.json"
            self.assertFalse(runtime.completed(path, "current"))
            for content in [
                "{",
                json.dumps({"run_id": "previous", "stage": "passed"}),
                json.dumps({"run_id": "current", "stage": "mixer"}),
            ]:
                path.write_text(content)
                self.assertFalse(runtime.completed(path, "current"))
            path.write_text(json.dumps({"run_id": "current", "stage": "passed"}))
            self.assertTrue(runtime.completed(path, "current"))


if __name__ == "__main__":
    unittest.main()
