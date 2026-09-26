"""Small source/geometry tests; no model or runtime execution is needed."""

import copy
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from convolution_lowering import decision, digest, unchanged

try:
    import numpy as np
    import onnx
except ImportError:
    np = onnx = None


def result_rows():
    return [
        {"kind": "retained", "name": role, "bitwise_equal": True, "control_bitwise_equal": True}
        for role in ["frozen", "full"]
    ] + [
        {"kind": "geometry", "name": name, "bitwise_equal": True}
        for name in ["zero", "ramp", "top_left", "bottom_right"]
    ]


class ProtocolTests(unittest.TestCase):
    def test_any_rounding_difference_stops_even_when_tolerance_passes(self):
        rows = result_rows()
        self.assertTrue(decision(rows)["experiment_1_passed"])
        rows[0].update(bitwise_equal=False, allclose=True)
        self.assertEqual(decision(rows)["next_action"], "stop-this-approach")
        self.assertFalse(decision(rows)["qualified"])
        self.assertFalse(decision(rows)["experiment_2_started"])

    def test_controls_missing_cases_and_duplicate_cases_cannot_pass(self):
        rows = result_rows()
        rows[1]["control_bitwise_equal"] = False
        self.assertFalse(decision(rows)["controls_valid"])
        for changed in [result_rows()[:-1], result_rows() + [result_rows()[0]]]:
            self.assertFalse(decision(changed)["experiment_1_passed"])
        rows = result_rows()
        rows[-1]["name"] = rows[-2]["name"]
        self.assertFalse(decision(rows)["experiment_1_passed"])

    def test_source_changes_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "source"
            path.write_bytes(b"original")
            sources = {str(path): digest(path)}
            unchanged(sources)
            path.write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "Changed experiment input"):
                unchanged(sources)


@unittest.skipIf(
    np is None or onnx is None, "Run geometry construction tests in the OCR environment"
)
class GraphConstructionTests(unittest.TestCase):
    def setUp(self):
        from convolution_lowering import conv_graph, geometry_cases

        self.cases = list(geometry_cases())
        _, self.input, self.weight, _ = self.cases[1]
        self.model = conv_graph(self.input, self.weight)

    def test_preserves_source_and_exact_weight_values_with_constant_right_operand(self):
        from convolution_lowering import lower

        before = self.model.SerializeToString()
        result = lower(self.model, self.input, self.weight)
        self.assertEqual(self.model.SerializeToString(), before)
        self.assertNotIn("Conv", [n.op_type for n in result.graph.node])
        matmul = next(n for n in result.graph.node if n.op_type == "MatMul")
        initializer = next(n for n in result.graph.initializer if n.name == matmul.input[1])
        actual = onnx.numpy_helper.to_array(initializer)
        self.assertEqual(actual.dtype, np.float32)
        self.assertEqual(actual.T.copy().tobytes(), self.weight.reshape(2, -1).tobytes())
        onnx.checker.check_model(result)

    def test_padding_and_patch_order_match_asymmetric_even_kernel(self):
        from convolution_lowering import lower

        result = lower(self.model, self.input, self.weight)
        constants = {
            i.name: onnx.numpy_helper.to_array(i).tolist() for i in result.graph.initializer
        }
        self.assertEqual(constants["pads"], [0, 0, 0, 0, 0, 0, 1, 1])
        self.assertEqual(constants["column_shape"], [1, 12, 15])
        concat = next(n for n in result.graph.node if n.op_type == "Concat")
        self.assertEqual(
            list(concat.input), [f"patch_{y}_{x}_axis" for y in range(2) for x in range(2)]
        )
        for y in range(2):
            for x in range(2):
                self.assertEqual(constants[f"patch_{y}_{x}_start"], [y, x])
                self.assertEqual(constants[f"patch_{y}_{x}_end"], [3 + y, 5 + x])

    def test_unknown_padding_weights_and_precision_fail_closed(self):
        from convolution_lowering import lower

        model = copy.deepcopy(self.model)
        next(a for a in model.graph.node[1].attribute if a.name == "auto_pad").s = b"SAME_LOWER"
        for graph, operand, weight in [
            (model, self.input, self.weight),
            (self.model, self.input.astype("float64"), self.weight),
            (self.model, self.input, self.weight + 1),
        ]:
            with self.assertRaises(ValueError):
                lower(graph, operand, weight)

    def test_integer_oracle_exposes_top_left_and_bottom_right_padding(self):
        zero, _, top_left, bottom_right = self.cases
        self.assertFalse(np.any(zero[3]))
        self.assertEqual(np.count_nonzero(top_left[3][:, :, 1:, :]), 0)
        self.assertEqual(np.count_nonzero(top_left[3][:, :, :, 1:]), 0)
        self.assertEqual(np.count_nonzero(bottom_right[3][:, :, :1, :]), 0)
        self.assertEqual(np.count_nonzero(bottom_right[3][:, :, :, :3]), 0)
        values = [1, 2, 4]
        for channel in range(2):
            self.assertEqual(
                top_left[3][0, channel, 0, 0],
                sum(values[c] * int(self.weight[channel, c, 0, 0]) for c in range(3)),
            )
            self.assertEqual(
                bottom_right[3][0, channel, 1, 3],
                sum(values[c] * int(self.weight[channel, c, 1, 1]) for c in range(3)),
            )


if __name__ == "__main__":
    unittest.main()
