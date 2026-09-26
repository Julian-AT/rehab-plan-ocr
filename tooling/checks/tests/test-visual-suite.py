import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image

spec = importlib.util.spec_from_file_location(
    "suite", Path(__file__).parents[1] / "compare-visual-suite.py"
)
suite = importlib.util.module_from_spec(spec)
spec.loader.exec_module(suite)


class VisualSuiteTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.baseline = self.root / "baseline"
        self.attachments = self.root / "attachments"
        self.baseline.mkdir()
        self.attachments.mkdir()
        entries, attachments = [], []
        for name in ["cards-light", "cards-dark"]:
            image = self.baseline / f"{name}.png"
            Image.new("RGB", (4, 200), "white").save(image)
            data = image.read_bytes()
            (self.attachments / image.name).write_bytes(data)
            entries.append({"file": image.name, "sha256": hashlib.sha256(data).hexdigest()})
            attachments.append(
                {
                    "exportedFileName": image.name,
                    "suggestedHumanReadableName": f"calm-{name}_0.png",
                    "isAssociatedWithFailure": False,
                }
            )
        (self.baseline / "baseline.json").write_text(json.dumps({"images": entries}))
        self.manifest = [
            {
                "attachments": attachments,
                "testIdentifier": suite.CAPTURE_TESTS[0],
                "testIdentifierURL": self.capture_url(suite.CAPTURE_TESTS[0]),
            }
        ]

    @staticmethod
    def capture_url(identifier):
        return "test://com.apple.xcode/Termine/TermineUITests/" + identifier.removesuffix("()")

    def capture_tree(self):
        return {
            "testNodes": [
                {
                    "nodeType": "Test Suite",
                    "children": [
                        {
                            "nodeType": "Test Case",
                            "nodeIdentifier": identifier,
                            "nodeIdentifierURL": self.capture_url(identifier),
                            "result": "Passed",
                        }
                        for identifier in suite.CAPTURE_TESTS
                    ],
                }
            ]
        }

    @staticmethod
    def passed_summary(count=3):
        return {
            "result": "Passed",
            "totalTestCount": count,
            "passedTests": count,
            "failedTests": 0,
            "skippedTests": 0,
        }

    def compare(self):
        (self.attachments / "manifest.json").write_text(json.dumps(self.manifest))
        return suite.compare_suite(self.baseline, self.attachments, self.root / "previews")

    def test_all_references_required_without_replacing_originals(self):
        before = {p.name: p.read_bytes() for p in self.baseline.iterdir()}
        result = self.compare()
        self.assertTrue(result["passed"])
        self.assertEqual(result["matching_images"], 2)
        self.assertFalse(result["full_app_regression_qualified"])
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.baseline.iterdir()})

    def test_missing_capture_and_changed_app_pixels_fail(self):
        self.manifest[0]["attachments"].pop()
        path = self.attachments / "cards-light.png"
        with Image.open(path) as image:
            image.putpixel((1, 170), (254, 255, 255))
            image.save(path)
        result = self.compare()
        self.assertFalse(result["passed"])
        self.assertEqual(result["matching_images"], 0)

    def test_duplicate_capture_is_not_silently_selected(self):
        self.manifest[0]["attachments"] *= 2
        result = self.compare()
        self.assertFalse(result["passed"])
        self.assertTrue(all("exactly one" in r["error"] for r in result["images"]))

    def test_picture_from_another_test_is_not_a_capture(self):
        self.manifest[0]["testIdentifier"] = suite.CAPTURE_TESTS[1]
        self.manifest[0]["testIdentifierURL"] = self.capture_url(suite.CAPTURE_TESTS[1])
        result = self.compare()
        self.assertFalse(result["passed"])
        self.assertTrue(all("declared test" in r["error"] for r in result["images"]))

    def test_required_capture_identities_can_belong_to_a_complete_larger_run(self):
        tree = self.capture_tree()
        self.assertTrue(suite.capture_test_status(self.passed_summary(), tree)["passed"])
        tree["testNodes"].append(
            {"nodeType": "Test Case", "nodeIdentifier": "Other/test()", "result": "Passed"}
        )
        status = suite.capture_test_status(self.passed_summary(4), tree)
        self.assertTrue(status["passed"])
        self.assertTrue(status["complete_run_passed"])
        self.assertEqual(len(status["required_tests"]), 3)

    def test_counts_cannot_substitute_missing_failed_skipped_or_retried_captures(self):
        for change in ("missing", "wrong-bundle", "failed", "skipped", "duplicate", "unknown"):
            with self.subTest(change=change):
                tree = self.capture_tree()
                cases = tree["testNodes"][0]["children"]
                if change == "missing":
                    cases.pop()
                elif change == "wrong-bundle":
                    cases[0]["nodeIdentifierURL"] = cases[0]["nodeIdentifierURL"].replace(
                        "/TermineUITests/", "/UnrelatedTests/"
                    )
                elif change == "duplicate":
                    cases.append(dict(cases[0]))
                else:
                    cases[0]["result"] = change.title()
                status = suite.capture_test_status(self.passed_summary(), tree)
                self.assertFalse(status["passed"])

    def test_failed_incomplete_or_skipped_surrounding_run_remains_failed(self):
        for change in (
            {"result": "Failed", "failedTests": 1},
            {"passedTests": 2},
            {"skippedTests": 1},
            {"totalTestCount": None},
            {"totalTestCount": True},
        ):
            with self.subTest(change=change):
                summary = self.passed_summary() | change
                self.assertFalse(suite.capture_test_status(summary, self.capture_tree())["passed"])

    def test_actual_surrounding_cases_must_match_the_successful_summary(self):
        for change in ("missing", "extra", "failed", "skipped"):
            with self.subTest(change=change):
                tree = self.capture_tree()
                summary = self.passed_summary(4)
                if change != "missing":
                    tree["testNodes"].append(
                        {
                            "nodeType": "Test Case",
                            "nodeIdentifier": "Other/test()",
                            "result": "Passed" if change == "extra" else change.title(),
                        }
                    )
                if change == "extra":
                    summary = self.passed_summary(3)
                status = suite.capture_test_status(summary, tree)
                self.assertFalse(status["passed"])
                self.assertFalse(status["complete_run_passed"])

    def test_export_indexes_only_a_disposable_copy_and_records_unchanged_original(self):
        bundle = self.root / "source.xcresult"
        bundle.mkdir()
        (bundle / "Data").write_bytes(b"complete original result")
        output = self.root / "export"
        output.mkdir()
        working_paths = []

        def run(args):
            working = Path(args[args.index("--path") + 1])
            working_paths.append(working)
            self.assertNotEqual(working, bundle)
            self.assertEqual((working / "Data").read_bytes(), b"complete original result")
            (working / "database.sqlite3").write_bytes(b"generated read index")
            if args[0] == "export":
                destination = Path(args[args.index("--output-path") + 1])
                destination.mkdir()
                (destination / "manifest.json").write_text("[]")
                return ""
            return '{"result":"Passed"}'

        self.assertEqual(suite.export_evidence(bundle, output, run), {"result": "Passed"})
        self.assertTrue((output / "test-tree.json").is_file())
        receipt = json.loads((output / "source-result.json").read_text())
        self.assertTrue(receipt["unchanged"])
        self.assertEqual(set(receipt["files"]), {"Data"})
        self.assertEqual(list(bundle.iterdir()), [bundle / "Data"])
        self.assertEqual(len(set(working_paths)), 1)
        self.assertTrue(all(not path.exists() for path in working_paths))

    def test_source_mutation_is_detected_and_nested_export_rejected(self):
        bundle = self.root / "source.xcresult"
        bundle.mkdir()
        source = bundle / "Data"
        source.write_text("original")
        output = self.root / "export"
        output.mkdir()

        def changed(_):
            source.write_text("concurrent change")
            raise RuntimeError("export interrupted")

        with self.assertRaisesRegex(ValueError, "Source result bundle changed"):
            suite.export_evidence(bundle, output, changed)
        self.assertFalse((output / "source-result.json").exists())
        with self.assertRaisesRegex(ValueError, "outside"):
            suite.export_evidence(bundle, bundle / "nested", changed)
        self.assertFalse((bundle / "nested").exists())

    def test_historical_result_is_not_attributed_to_the_current_app_checkout(self):
        output = self.root / ".local/runs/review"
        helper = self.root / "tooling/utils/xcresult.py"
        helper.parent.mkdir(parents=True)
        helper.write_bytes((suite.ROOT / "tooling/utils/xcresult.py").read_bytes())
        (helper.parent / "apfs_clone.py").write_bytes(
            (suite.ROOT / "tooling/utils/apfs_clone.py").read_bytes()
        )

        def export(_, destination):
            attachments = destination / "attachments"
            attachments.mkdir()
            for path in self.attachments.iterdir():
                (attachments / path.name).write_bytes(path.read_bytes())
            (attachments / "manifest.json").write_text(json.dumps(self.manifest))
            (destination / "source-result.json").write_text("{}")
            (destination / "test-tree.json").write_text(json.dumps(self.capture_tree()))
            return self.passed_summary()

        with (
            patch.object(suite, "ROOT", self.root),
            patch.object(suite, "BASELINE", self.baseline),
            patch.object(suite, "export_evidence", side_effect=export),
            patch.object(
                suite, "source_snapshot", side_effect=AssertionError("Not the tested source")
            ),
            patch.object(
                suite.workspace,
                "location",
                side_effect=AssertionError("Current build storage is unrelated to old results"),
            ),
            patch.object(suite.subprocess, "check_output", return_value="b" * 40),
            patch(
                "sys.argv",
                [
                    "compare",
                    "--xcresult",
                    str(self.root / "historical.xcresult"),
                    "--run",
                    str(output),
                ],
            ),
            patch("builtins.print"),
        ):
            suite.main()
        report = json.loads((output / "report.json").read_text())
        self.assertTrue(report["passed"])
        self.assertEqual(report["evaluator_revision"], "b" * 40)
        self.assertIsNone(report["source_revision"])
        self.assertNotIn("sources", report)
        self.assertEqual(report["capture_mode"], "provided-result")


if __name__ == "__main__":
    unittest.main()
