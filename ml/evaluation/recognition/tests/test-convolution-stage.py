"""Fixed case selection and dynamic graph construction without model inference."""

import copy
import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from convolution_stage import select_cases

try:
    import numpy as np
    import onnx
except ImportError:
    np = onnx = None


class SelectionTests(unittest.TestCase):
    def test_six_unique_cases_include_both_widths_and_prior_passes(self):
        rows = [
            {
                "id": name,
                "width": width,
                "allclose": passed,
                "same_tokens": True,
                "max_absolute_error": error,
            }
            for width in [320, 640]
            for name, passed, error in [
                ("pass", True, 0.01),
                ("first", False, 0.9),
                ("worst-other", False, 0.8),
                ("other", False, 0.1),
            ]
        ]
        chosen = select_cases(rows)
        self.assertEqual([r["prior"]["id"] for r in chosen], ["first", "worst-other", "pass"] * 2)
        self.assertEqual(len({(r["prior"]["id"], r["prior"]["width"]) for r in chosen}), 6)
        self.assertEqual(sum(r["prior"]["allclose"] for r in chosen), 2)
        with self.assertRaisesRegex(ValueError, "duplicate"):
            select_cases(rows + [rows[0]])
        with self.assertRaisesRegex(ValueError, "cannot supply"):
            select_cases(rows[:4])


@unittest.skipIf(np is None or onnx is None, "Run graph construction tests in the OCR environment")
class DynamicGraphTests(unittest.TestCase):
    def setUp(self):
        from convolution_lowering import conv_graph

        self.weights = [
            (np.arange(24 * 48 * 4, dtype=np.float32).reshape(24, 48, 2, 2) % 7) - 3,
            (np.arange(48 * 24 * 4, dtype=np.float32).reshape(48, 24, 2, 2) % 7) - 3,
        ]
        nodes = []
        for index, weight in enumerate(self.weights):
            part = conv_graph(np.zeros((1, weight.shape[1], 1, 1), dtype=np.float32), weight)
            constant, conv = copy.deepcopy(list(part.graph.node))
            constant.output[0] = f"weight-{index}"
            conv.input[0], conv.input[1] = ("input" if index == 0 else "middle"), constant.output[0]
            conv.output[0] = "middle" if index == 0 else "output"
            nodes.extend([constant, conv])
        self.model = onnx.helper.make_model(
            onnx.helper.make_graph(
                nodes,
                "two-stem-convs",
                [
                    onnx.helper.make_tensor_value_info(
                        "input", onnx.TensorProto.FLOAT, ["N", 48, "H", "W"]
                    )
                ],
                [
                    onnx.helper.make_tensor_value_info(
                        "output", onnx.TensorProto.FLOAT, ["N", 48, "H", "W"]
                    )
                ],
            ),
            opset_imports=[onnx.helper.make_opsetid("", 17)],
            ir_version=8,
        )

    def test_only_two_convs_change_and_dynamic_shape_is_preserved(self):
        from convolution_stage import lower_model

        before = self.model.SerializeToString()
        candidate, replacements = lower_model(self.model)
        self.assertEqual(self.model.SerializeToString(), before)
        self.assertEqual(len(replacements), 2)
        self.assertEqual(candidate.graph.input[0], self.model.graph.input[0])
        self.assertEqual(candidate.graph.output[0], self.model.graph.output[0])
        self.assertEqual(
            [n for n in candidate.graph.node if n.op_type == "Constant"],
            [n for n in self.model.graph.node if n.op_type == "Constant"],
        )
        self.assertEqual(sum(n.op_type == "Shape" for n in candidate.graph.node), 2)
        self.assertEqual(sum(n.op_type == "MatMul" for n in candidate.graph.node), 2)
        self.assertFalse(any(n.op_type == "Conv" for n in candidate.graph.node))
        initializers = {i.name: i for i in candidate.graph.initializer}
        for index, weight in enumerate(self.weights):
            prefix = f"conv_lowering/{index}/"
            for dynamic in ["column_shape", "output_shape", "patch_0_0_end", "patch_1_1_end"]:
                self.assertNotIn(prefix + dynamic, initializers)
            right = onnx.numpy_helper.to_array(initializers[prefix + "right_weights"])
            self.assertEqual(
                right.T.copy().tobytes(), weight.reshape(weight.shape[0], -1).tobytes()
            )
        onnx.checker.check_model(candidate)

    def test_unknown_geometry_or_missing_second_stem_is_rejected(self):
        from convolution_stage import lower_model

        bad = copy.deepcopy(self.model)
        next(a for a in bad.graph.node[1].attribute if a.name == "group").i = 2
        with self.assertRaisesRegex(ValueError, "geometry"):
            lower_model(bad)
        missing = copy.deepcopy(self.model)
        del missing.graph.node[2:]
        with self.assertRaisesRegex(ValueError, "exactly the two"):
            lower_model(missing)

    @unittest.skipUnless(
        os.environ.get("OCR_RUNTIME_TESTS") == "1", "Requires a scheduled runtime window"
    )
    def test_dynamic_batch_and_odd_width_against_exact_integer_stencils(self):
        import onnxruntime as ort
        from convolution_stage import lower_model

        candidate, _ = lower_model(self.model)
        options = ort.SessionOptions()
        options.intra_op_num_threads, options.inter_op_num_threads = 2, 1
        session = ort.InferenceSession(
            candidate.SerializeToString(), sess_options=options, providers=["CPUExecutionProvider"]
        )
        for shape in [(1, 48, 3, 5), (2, 48, 4, 7)]:
            operand = (np.arange(np.prod(shape)).reshape(shape) % 5 - 2).astype(np.float32)
            expected = operand.astype(np.int64)
            for weight in self.weights:
                padded = np.pad(expected, ((0, 0), (0, 0), (0, 1), (0, 1)))
                result = np.zeros((shape[0], weight.shape[0], shape[2], shape[3]), dtype=np.int64)
                for y in range(shape[2]):
                    for x in range(shape[3]):
                        result[:, :, y, x] = np.tensordot(
                            padded[:, :, y : y + 2, x : x + 2],
                            weight.astype(np.int64),
                            axes=([1, 2, 3], [1, 2, 3]),
                        )
                expected = result
            actual = session.run(None, {"input": operand})[0]
            self.assertEqual(actual.dtype, np.float32)
            self.assertEqual(actual.shape, expected.shape)
            self.assertEqual(actual.tobytes(), expected.astype(np.float32).tobytes())


if __name__ == "__main__":
    unittest.main()
