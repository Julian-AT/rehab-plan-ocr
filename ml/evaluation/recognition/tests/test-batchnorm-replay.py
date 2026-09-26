"""Inference-only replay must preserve channel semantics and the declared arithmetic."""

import copy
import importlib.util
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import batchnorm_replay as replay

HAS_ARRAYS = all(importlib.util.find_spec(name) for name in ["numpy", "onnx", "onnxruntime"])


class BatchNormReplayTests(unittest.TestCase):
    def test_training_layout_and_changed_statistics_are_rejected(self):
        original = {
            "is_test": True,
            "use_global_stats": True,
            "trainable_statistics": False,
            "data_format": "NCHW",
            "epsilon": 1e-5,
            "momentum": 0.9,
        }
        replay.validate_attributes(original, {"training_mode": 0})
        for key, value in [
            ("is_test", False),
            ("use_global_stats", False),
            ("trainable_statistics", True),
            ("data_format", "NHWC"),
            ("epsilon", 1e-3),
            ("momentum", 0.8),
        ]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                replay.validate_attributes(original | {key: value}, {"training_mode": 0})
        with self.assertRaises(ValueError):
            replay.validate_attributes(original, {"training_mode": 1})

    @unittest.skipUnless(HAS_ARRAYS, "Pinned OCR arrays/runtime are unavailable")
    def test_channel_broadcasting_and_parameters_are_preserved(self):
        import numpy as np
        import onnx
        import onnxruntime as ort

        operand = np.arange(48, dtype=np.float32).reshape(2, 3, 2, 4)
        parameters = [
            np.asarray(x, dtype=np.float32) for x in [[2, -4, 8], [3, 5, 7], [1, 2, 3], [4, 16, 64]]
        ]
        before = copy.deepcopy([operand, *parameters])
        expected = operand + np.asarray([2, 7, 4], dtype=np.float32).reshape(1, 3, 1, 1)
        expected[:, 1] = -operand[:, 1] + 7
        for grouping in ["paddle", "ort"]:
            graph = replay.expression_graph(
                operand, parameters, 0, grouping, [onnx.helper.make_opsetid("", 17)], 8
            )
            options = ort.SessionOptions()
            options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_DISABLE_ALL
            options.intra_op_num_threads, options.inter_op_num_threads = 1, 1
            session = ort.InferenceSession(
                graph.SerializeToString(), options, providers=["CPUExecutionProvider"]
            )
            np.testing.assert_array_equal(session.run(None, {"input": operand})[0], expected)
        for original, current in zip(before, [operand, *parameters], strict=True):
            np.testing.assert_array_equal(original, current)

    @unittest.skipUnless(HAS_ARRAYS, "Pinned OCR arrays/runtime are unavailable")
    def test_only_source_derived_groupings_and_matching_fp32_channels_are_accepted(self):
        import numpy as np
        import onnx

        operand = np.ones((1, 3, 2, 4), dtype=np.float32)
        parameters = [np.ones(3, dtype=np.float32) for _ in range(4)]
        opset = [onnx.helper.make_opsetid("", 17)]
        for pixels, values, mode in [
            (operand, parameters, "search"),
            (operand.astype(np.float64), parameters, "paddle"),
            (operand, parameters[:3], "paddle"),
            (operand, [*parameters[:3], np.ones(2, dtype=np.float32)], "paddle"),
        ]:
            with self.assertRaises(ValueError):
                replay.expression_graph(pixels, values, 1e-5, mode, opset, 8)


if __name__ == "__main__":
    unittest.main()
