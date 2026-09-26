"""Missing selections, misleading counts and stale evidence must fail the UI gate."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "ui_result", Path(__file__).resolve().parents[1] / "ui-test-result.py"
)
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


def case(method="testFirst", target="TermineUITests", result="Passed"):
    return {
        "nodeType": "Test Case",
        "nodeIdentifier": f"Example/{method}()",
        "nodeIdentifierURL": f"test://com.apple.xcode/Termine/{target}/Example/{method}",
        "result": result,
    }


def tree(*cases):
    return {"testNodes": [{"children": [{"children": list(cases)}]}]}


def summary(count=1):
    return {
        "result": "Passed",
        "totalTestCount": count,
        "passedTests": count,
        "failedTests": 0,
        "skippedTests": 0,
    }


class ResultGateTests(unittest.TestCase):
    def test_exit_success_and_one_pass_cannot_replace_two_requested_methods(self):
        required = ["TermineUITests/Example/testFirst", "TermineUITests/Example/testSecond"]
        result = gate.selection_status(summary(), tree(case()), required)
        self.assertFalse(result["passed"])
        self.assertTrue(result["complete_run_passed"])
        self.assertFalse(result["requested_tests"][1]["present"])
        self.assertTrue(
            gate.selection_status(summary(2), tree(case(), case("testSecond")), required)["passed"]
        )

    def test_method_name_prefix_or_foreign_target_cannot_satisfy_selection(self):
        required = ["TermineUITests/Example/testFirst"]
        for actual in [case("testFirstExtra"), case(target="ForeignTests")]:
            self.assertFalse(gate.selection_status(summary(), tree(actual), required)["passed"])
        forged = case() | {"nodeIdentifier": "Example/testDifferent()"}
        self.assertFalse(gate.selection_status(summary(), tree(forged), required)["passed"])

    def test_empty_skipped_failed_duplicated_and_inconsistent_runs_fail(self):
        for actual, tests in [
            (summary(0), tree()),
            (summary() | {"totalTestCount": True}, tree(case())),
            (summary() | {"result": "Failed"}, tree(case())),
            (summary() | {"failedTests": 1}, tree(case())),
            (summary() | {"skippedTests": 1}, tree(case())),
            (summary(2), tree(case())),
            (summary(2), tree(case(), case())),
            (summary(), tree(case(result="Skipped"))),
            (summary(), tree(case(result="Failed"))),
        ]:
            self.assertFalse(gate.selection_status(actual, tests, [])["passed"])

    def test_target_and_class_selections_require_execution_without_claiming_enumeration(self):
        result = gate.selection_status(
            summary(), tree(case()), ["TermineUITests", "TermineUITests/Example"]
        )
        self.assertTrue(result["passed"])
        self.assertFalse(result["suite_enumeration_verified"])
        self.assertFalse(
            gate.selection_status(summary(), tree(case()), ["TermineUITests/Other"])["passed"]
        )

    def test_repeated_option_forms_retain_every_request_and_reject_malformed_values(self):
        self.assertEqual(
            gate.selections(
                [
                    "-only-testing:TermineUITests/Example/testFirst",
                    "-only-testing",
                    "TermineUITests/Example/testSecond()",
                    "-only-testing:TermineUITests/Example/testFirst",
                ]
            ),
            ["TermineUITests/Example/testFirst", "TermineUITests/Example/testSecond"],
        )
        for args in [
            ["-only-testing"],
            ["-only-testing:"],
            ["-only-testing:T//M"],
            ["-only-testing:T/C/M/Extra"],
            ["-only-testing", "-resultBundlePath"],
        ]:
            with self.assertRaises(ValueError):
                gate.selections(args)

    def test_existing_result_or_verification_blocks_execution(self):
        with tempfile.TemporaryDirectory() as folder:
            bundle = Path(folder) / "result.xcresult"
            output = bundle.with_name(bundle.name + ".verification")
            for existing in [bundle, output]:
                existing.write_text("protected evidence")
                with patch.object(gate.subprocess, "run") as run, self.assertRaises(ValueError):
                    gate.execute(["-resultBundlePath", str(bundle)])
                run.assert_not_called()
                self.assertEqual(existing.read_text(), "protected evidence")
                existing.unlink()

    def test_relative_result_is_checked_in_the_xcode_working_directory(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "existing.xcresult").write_text("protected evidence")
            with (
                patch.object(gate, "ROOT", root),
                patch.object(gate.subprocess, "run") as run,
                self.assertRaises(ValueError),
            ):
                gate.execute(["-resultBundlePath", "existing.xcresult"])
            run.assert_not_called()

    def test_export_uses_disposable_copy_and_keeps_original_and_previous_report(self):
        with tempfile.TemporaryDirectory() as folder:
            bundle = Path(folder) / "result.xcresult"
            bundle.mkdir()
            (bundle / "Data").write_bytes(b"immutable source")
            output = Path(folder) / "verification"

            def run(args):
                working = Path(args[args.index("--path") + 1])
                self.assertNotEqual(working, bundle)
                (working / "generated-index").write_bytes(b"temporary")
                return json.dumps(summary() if args[2] == "summary" else tree(case()))

            result = gate.verify(bundle, output, ["TermineUITests/Example/testFirst"], run=run)
            self.assertTrue(result["passed"])
            self.assertTrue(result["source_result"]["unchanged"])
            self.assertEqual(list(bundle.iterdir()), [bundle / "Data"])
            before = (output / "verification.json").read_bytes()
            with self.assertRaises(FileExistsError):
                gate.verify(bundle, output, [], run=run)
            self.assertEqual((output / "verification.json").read_bytes(), before)
            with self.assertRaises(ValueError):
                gate.verify(bundle, bundle / "nested", [], run=run)

    def test_failed_command_cannot_be_overridden_by_a_passed_report(self):
        with tempfile.TemporaryDirectory() as folder:
            bundle = Path(folder) / "result.xcresult"

            def execute(*args, **kwargs):
                bundle.mkdir()
                return gate.subprocess.CompletedProcess(args[0], 65)

            def verify(source, output, required):
                output.mkdir()
                return {"passed": True, "requested_tests": []}

            with (
                patch.object(gate.subprocess, "run", side_effect=execute),
                patch.object(gate, "verify", side_effect=verify),
            ):
                self.assertEqual(gate.execute(["-resultBundlePath", str(bundle)]), 65)


if __name__ == "__main__":
    unittest.main()
