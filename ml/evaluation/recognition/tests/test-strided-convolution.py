"""Independent geometry and gate checks; retained model execution is separate."""

import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from strided_convolution import GEOMETRY, LEVELS, decision

try:
    import numpy as np
    import onnx
    from onnx.reference import ReferenceEvaluator
except ImportError:
    np = onnx = ReferenceEvaluator = None


class GateTests(unittest.TestCase):
    def setUp(self):
        self.rows = [
            {"name": name, "level": level, "bitwise_equal": True, "reload_bitwise_equal": True}
            for name in [*GEOMETRY, "retained"]
            for level in LEVELS
        ]
        self.controls = {
            name: {"bitwise_equal": True} for name in ["input", "weights", "paddle", "onnx"]
        }

    def test_all_cases_and_controls_are_required_in_the_frozen_order(self):
        self.assertTrue(decision(self.rows, self.controls)["lowering_passed"])
        for rows in [self.rows[:-1], self.rows + [self.rows[0]], list(reversed(self.rows))]:
            self.assertFalse(decision(rows, self.controls)["lowering_passed"])
        self.rows[1] = self.rows[0]
        self.assertFalse(decision(self.rows, self.controls)["lowering_passed"])

    def test_tolerance_cannot_override_byte_or_reload_controls(self):
        for field in ["bitwise_equal", "reload_bitwise_equal"]:
            rows = copy.deepcopy(self.rows)
            rows[-1][field] = False
            rows[-1]["allclose"] = True
            self.assertFalse(decision(rows, self.controls)["lowering_passed"])
        for key in self.controls:
            controls = copy.deepcopy(self.controls)
            controls[key]["bitwise_equal"] = False
            self.assertFalse(decision(self.rows, controls)["lowering_passed"])
        self.assertFalse(decision(self.rows, {})["controls_valid"])
        result = decision(self.rows, self.controls)
        self.assertFalse(result["qualified"])
        self.assertFalse(result["full_graph_started"])


@unittest.skipIf(np is None or onnx is None, "Run geometry checks in the OCR environment")
class GeometryTests(unittest.TestCase):
    def setUp(self):
        from strided_convolution import geometry_cases, graph

        self.cases = list(geometry_cases())
        _, self.x, self.w, self.expected = self.cases[1]
        self.model = graph(self.x, self.w)

    def test_reference_executor_matches_independent_integer_oracle_at_all_borders(self):
        from strided_convolution import graph, lower

        for name, x, w, expected in self.cases:
            with self.subTest(name=name):
                original = graph(x, w)
                candidate = lower(original, x, w)
                for model in [original, candidate]:
                    actual = ReferenceEvaluator(model).run(None, {"input": x})[0]
                    np.testing.assert_array_equal(actual, expected)
                    self.assertEqual(actual.dtype, np.float32)
        self.assertTrue(np.any(self.cases[2][3]))
        self.assertTrue(np.any(self.cases[3][3]))

    def test_source_and_weights_are_preserved_without_convolution_nodes(self):
        from strided_convolution import lower

        before = self.model.SerializeToString()
        candidate = lower(self.model, self.x, self.w)
        self.assertEqual(before, self.model.SerializeToString())
        self.assertNotIn("Conv", [n.op_type for n in candidate.graph.node])
        value = next(v for v in candidate.graph.initializer if v.name == "stride_weights")
        self.assertEqual(
            onnx.numpy_helper.to_array(value).T.copy().tobytes(), self.w.reshape(2, -1).tobytes()
        )
        onnx.checker.check_model(candidate)

    def test_changed_geometry_bias_precision_and_weights_are_rejected(self):
        from strided_convolution import lower

        for field in ["strides", "pads", "dilations", "group"]:
            changed = copy.deepcopy(self.model)
            attr = next(a for a in changed.graph.node[1].attribute if a.name == field)
            if field == "group":
                attr.i = 2
            else:
                attr.ints[0] += 1
            with self.assertRaisesRegex(ValueError, "geometry"):
                lower(changed, self.x, self.w)
        bias = copy.deepcopy(self.model)
        bias.graph.node[1].input.append("bias")
        for model, x, w in [
            (bias, self.x, self.w),
            (self.model, self.x.astype(np.float64), self.w),
            (self.model, self.x, self.w + 1),
            (self.model, self.x[:, :, :-1], self.w),
        ]:
            with self.assertRaises(ValueError):
                lower(model, x, w)

    def test_signed_zero_weights_and_nonfinite_inputs_are_not_silently_changed(self):
        from strided_convolution import graph, lower

        w = self.w.copy()
        w[0, 0, 0, 0] = 0.0
        model = graph(self.x, w)
        changed = w.copy()
        changed[0, 0, 0, 0] = -0.0
        with self.assertRaisesRegex(ValueError, "weights"):
            lower(model, self.x, changed)
        x = self.x.copy()
        x[0, 0, 0, 0] = np.nan
        with self.assertRaisesRegex(ValueError, "finite"):
            lower(model, x, w)


if __name__ == "__main__":
    unittest.main()
