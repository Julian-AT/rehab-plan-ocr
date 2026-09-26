import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "triage", Path(__file__).resolve().parents[1] / "collect-native-triage.py"
)
triage = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(triage)


class TriageTests(unittest.TestCase):
    def test_failed_tests_retain_text_and_crashes_without_copying_videos_or_changing_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bundle = root / "source.xcresult"
            bundle.mkdir()
            (bundle / "Data").write_bytes(b"original complete result")
            before = triage.inventory(bundle)
            calls = []

            def run(args):
                calls.append(args)
                # A fresh downloaded xcresult gets an index even on a read request.
                working = Path(args[args.index("--path") + 1])
                self.assertNotEqual(working, bundle)
                (working / "database.sqlite3").write_bytes(b"derived index")
                if args[:2] == ["export", "attachments"]:
                    destination = Path(args[-1])
                    (destination / "crash.ips").write_text("synthetic crash")
                    (destination / "screen.mp4").write_bytes(b"synthetic video")
                    return ""
                if args[2] == "summary":
                    return json.dumps(
                        {"testFailures": [{"testIdentifierString": "Suite/test()"}] * 2}
                    )
                return "{}"

            output = root / "triage"
            result = triage.collect(bundle, output, "a" * 40, run)
            self.assertEqual(result["status"], "collected")
            self.assertEqual(result["failed_test_identifiers"], ["Suite/test()"])
            self.assertIn("failure-001/crash.ips", result["files"])
            self.assertIn("failure-001/screen.mp4", result["omitted_videos"])
            self.assertFalse((output / "failure-001/screen.mp4").exists())
            self.assertEqual(triage.inventory(bundle), before)
            self.assertEqual(len(calls), 4)
            with self.assertRaises(FileExistsError):
                triage.collect(bundle, output, "a" * 40, run)

    def test_missing_result_is_reported_and_failed_collection_stays_incomplete(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = triage.collect(root / "missing", root / "missing-report", "a" * 40)
            self.assertEqual(result["status"], "result-unavailable")
            bundle = root / "source"
            bundle.mkdir()
            (bundle / "Data").write_text("fixture")

            def fail(_):
                raise RuntimeError("export failed")

            with self.assertRaisesRegex(RuntimeError, "export failed"):
                triage.collect(bundle, root / "failed", "a" * 40, fail)
            result = json.loads((root / "failed/receipt.json").read_text())
            self.assertEqual(result["status"], "collection-failed")

    def test_unidentified_or_nested_output_cannot_mutate_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for output, commit in [(root / "new", "short"), (root / "source/new", "a" * 40)]:
                with self.assertRaises(ValueError):
                    triage.collect(root / "source", output, commit)
                self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
