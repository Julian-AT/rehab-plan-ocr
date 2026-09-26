"""A partial or perturbed trace cannot establish the earliest operation or qualification."""

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import convolution_trace as trace


class ConvolutionTraceTests(unittest.TestCase):
    def test_unmapped_earlier_output_prevents_an_earliest_operation_claim(self):
        rows = [
            {"program_index": 3, "bitwise_equal": True, "allclose": True},
            {"program_index": 7, "bitwise_equal": False, "allclose": True},
        ]
        missing = [{"program_index": 4, "name": "unobserved"}]
        result = trace.trace_conclusion(rows, missing, True)
        self.assertEqual(result["first_mapped_difference"], rows[1])
        self.assertEqual(result["unmapped_before_difference"], missing)
        self.assertFalse(result["earliest_operation_established"])
        self.assertFalse(result["qualified"])

    def test_complete_prefix_can_establish_diagnostic_rounding_but_never_qualification(self):
        row = {"program_index": 7, "bitwise_equal": False, "allclose": True}
        result = trace.trace_conclusion([row], [{"program_index": 8}], True)
        self.assertTrue(result["earliest_operation_established"])
        self.assertTrue(result["first_mapped_difference"]["allclose"])
        self.assertFalse(result["qualified"])

    def test_perturbed_instrumentation_and_absent_differences_establish_nothing(self):
        row = {"program_index": 7, "bitwise_equal": False, "allclose": False}
        for rows, valid in [([row], False), ([], True)]:
            with self.subTest(rows=rows, valid=valid):
                result = trace.trace_conclusion(rows, [], valid)
                self.assertIsNone(result["first_mapped_difference"])
                self.assertFalse(result["earliest_operation_established"])
                self.assertFalse(result["qualified"])

    def test_preparation_preserves_inputs_and_refuses_changed_candidate_or_reuse(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            stage = root / "stage"
            (stage / "frozen").mkdir(parents=True)
            candidate = stage / "frozen/recognizer.onnx"
            candidate.write_bytes(b"immutable test graph")
            protocol = {
                "sources": {},
                "packages": {},
                "runs": [{"run": "source", "unfused": "unfused", "cases": [{"id": "first"}]}],
            }
            (stage / "protocol.json").write_text(json.dumps(protocol))
            report = {
                "experiment_2_passed": False,
                "cases": [{"role": "frozen", "width": 320}],
                "protocol_sha256": trace.digest(stage / "protocol.json"),
                "runs": [{"artifact_sha256": trace.digest(candidate)}],
            }
            (stage / "report.json").write_text(json.dumps(report))
            before = {str(path): path.read_bytes() for path in stage.rglob("*") if path.is_file()}
            with (
                patch.object(trace, "STAGE", stage),
                patch.object(trace, "STAGE_REPORT", trace.digest(stage / "report.json")),
                patch("builtins.print"),
            ):
                trace.prepare(root / "new")
                self.assertEqual(before, {name: Path(name).read_bytes() for name in before})
                prepared = json.loads((root / "new/protocol.json").read_text())
                self.assertFalse(prepared["rule"]["qualified"])
                self.assertIn(str(candidate), prepared["sources"])
                with self.assertRaises(FileExistsError):
                    trace.prepare(root / "new")
                candidate.write_bytes(b"changed graph")
                with self.assertRaisesRegex(ValueError, "candidate changed"):
                    trace.prepare(root / "rejected")
                self.assertFalse((root / "rejected").exists())


if __name__ == "__main__":
    unittest.main()
