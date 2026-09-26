"""Independent inference semantics and original-graph preservation controls."""

import copy
import importlib.util
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from batchnorm_graph import lower_batchnorm
from batchnorm_onnx import LEVELS, session

HAS_RUNTIME = all(importlib.util.find_spec(name) for name in ["numpy", "onnx", "onnxruntime"])


@unittest.skipUnless(HAS_RUNTIME, "Pinned OCR arrays/runtime unavailable")
class GraphTests(unittest.TestCase):
    def model(self, *, constants_as_nodes=False, shape=None):
        import numpy as np
        import onnx

        shape = shape or ["batch", 3, 2, "width"]
        arrays = [[2, -4, 8], [3, 5, 7], [1, 2, 3], [4, 16, 64]]
        constants = [
            onnx.numpy_helper.from_array(np.asarray(value, dtype=np.float32), name)
            for name, value in zip(["scale", "bias", "mean", "variance"], arrays, strict=True)
        ]
        nodes = [
            onnx.helper.make_node("Identity", ["input"], ["operand"], name="original-identity")
        ]
        initializers = constants
        if constants_as_nodes:
            nodes += [
                onnx.helper.make_node("Constant", [], [value.name], value=value)
                for value in constants
            ]
            initializers = []
        nodes += [
            onnx.helper.make_node(
                "BatchNormalization",
                ["operand", "scale", "bias", "mean", "variance"],
                ["output"],
                epsilon=0.0,
                training_mode=0,
            )
        ]
        graph = onnx.helper.make_graph(
            nodes,
            "independent-exact-affine",
            [onnx.helper.make_tensor_value_info("input", onnx.TensorProto.FLOAT, shape)],
            [onnx.helper.make_tensor_value_info("output", onnx.TensorProto.FLOAT, shape)],
            initializers,
        )
        return onnx.helper.make_model(
            graph, opset_imports=[onnx.helper.make_opsetid("", 17)], ir_version=8
        )

    def test_dynamic_batch_width_and_negative_scale_remain_exact(self):
        import numpy as np

        for as_nodes in [False, True]:
            transformed, receipts = lower_batchnorm(self.model(constants_as_nodes=as_nodes))
            self.assertEqual(len(receipts), 1)
            for batch, width in [(1, 4), (2, 7)]:
                pixels = np.arange(batch * 3 * 2 * width, dtype=np.float32).reshape(
                    batch, 3, 2, width
                )
                expected = pixels.copy()
                expected[:, 0] += 2
                expected[:, 1] = -pixels[:, 1] + 7
                expected[:, 2] += 4
                for level in LEVELS:
                    actual = session(transformed, level).run(None, {"input": pixels})[0]
                    self.assertEqual(actual.tobytes(), expected.tobytes())

    def test_original_nodes_constants_and_public_identities_do_not_change(self):
        original = self.model(constants_as_nodes=True)
        before = original.SerializeToString()
        candidate, receipts = lower_batchnorm(original)
        self.assertEqual(original.SerializeToString(), before)
        retained = [n for n in candidate.graph.node if not n.name.startswith("batchnorm_division/")]
        self.assertEqual(
            [n.SerializeToString() for n in retained],
            [n.SerializeToString() for n in original.graph.node[:-1]],
        )
        self.assertEqual(list(candidate.graph.input), list(original.graph.input))
        self.assertEqual(list(candidate.graph.output), list(original.graph.output))
        self.assertEqual(receipts[0]["output"], "output")
        self.assertEqual(receipts[0]["channels"], 3)

    def test_training_rank_dtype_and_duplicate_transformation_are_rejected(self):
        import onnx

        original = self.model()
        training = copy.deepcopy(original)
        next(a for a in training.graph.node[-1].attribute if a.name == "training_mode").i = 1
        rank = self.model(shape=[1, 3, 2])
        dtype = copy.deepcopy(original)
        dtype.graph.input[0].type.tensor_type.elem_type = onnx.TensorProto.DOUBLE
        transformed, _ = lower_batchnorm(original)
        for model in [training, rank, dtype, transformed]:
            with self.assertRaises(
                (ValueError, onnx.onnx_cpp2py_export.shape_inference.InferenceError)
            ):
                lower_batchnorm(model)

    def test_nonconstant_parameters_and_invalid_variance_are_rejected(self):
        import numpy as np
        import onnx

        for kind in ["missing", "negative", "zero", "channels"]:
            model = self.model()
            if kind == "missing":
                model.graph.node[-1].input[1] = "unknown_scale"
            else:
                variance = model.graph.initializer[-1]
                values = (
                    [-1, 16, 64]
                    if kind == "negative"
                    else [0, 16, 64]
                    if kind == "zero"
                    else [4, 16]
                )
                variance.CopyFrom(
                    onnx.numpy_helper.from_array(np.asarray(values, dtype=np.float32), "variance")
                )
            with (
                self.subTest(kind=kind),
                self.assertRaises(
                    (ValueError, onnx.onnx_cpp2py_export.shape_inference.InferenceError)
                ),
            ):
                lower_batchnorm(model)


if __name__ == "__main__":
    unittest.main()
