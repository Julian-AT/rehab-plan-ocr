"""A successful process launch is not evidence of complete native inference checks."""

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
from ml.evaluation.conversation.native import completed  # noqa: E402


class NativeCompletionTests(unittest.TestCase):
    def test_requires_fresh_complete_output_and_every_runtime_check(self):
        request = {
            "runID": "current",
            "model": {"sha256": "model"},
            "cases": [{"id": "one"}, {"id": "two"}],
        }
        valid = {
            "run_id": "current",
            "model_sha256": "model",
            "stage": "passed",
            "qualified": False,
            "cases": [{"id": "one", "output": "{}"}, {"id": "two", "output": "{}"}],
            **{
                name: True
                for name in [
                    "cancellation_passed",
                    "deadline_passed",
                    "context_limit_passed",
                    "output_limit_passed",
                    "state_isolation_passed",
                    "reload_passed",
                ]
            },
        }
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "report.json"
            self.assertFalse(completed(path, request))
            path.write_text("{")
            self.assertFalse(completed(path, request))
            path.write_text(json.dumps(valid))
            self.assertTrue(completed(path, request))
            mutations = {
                "run_id": "old",
                "model_sha256": "wrong",
                "stage": "generating",
                "qualified": True,
                "cases": [{"id": "one", "output": "{}"}],
            }
            for key, replacement in mutations.items():
                with self.subTest(field=key):
                    path.write_text(json.dumps(dict(valid, **{key: replacement})))
                    self.assertFalse(completed(path, request))
            for key in valid:
                incomplete = dict(valid)
                incomplete.pop(key)
                path.write_text(json.dumps(incomplete))
                self.assertFalse(completed(path, request), key)
            for changed_cases in [
                list(reversed(valid["cases"])),
                [valid["cases"][0]] * 2,
                [{"id": "one", "output": ""}, valid["cases"][1]],
            ]:
                path.write_text(json.dumps(dict(valid, cases=changed_cases)))
                self.assertFalse(completed(path, request))
            empty = copy.deepcopy(request)
            empty["cases"] = []
            path.write_text(json.dumps(dict(valid, cases=[])))
            self.assertFalse(completed(path, empty))


if __name__ == "__main__":
    unittest.main()
