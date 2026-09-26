"""Synthetic ONNX arithmetic and transformation controls, without saved model inputs."""

import copy
import importlib.util
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import batchnorm_onnx as diagnostic
from batchnorm_replay import expression_graph

HAS_RUNTIME = all(importlib.util.find_spec(name) for name in ["numpy", "onnx", "onnxruntime"])


@unittest.skipUnless(HAS_RUNTIME, "Pinned OCR arrays/runtime unavailable")
class DivisionTests(unittest.TestCase):
    def graph(self):
        import numpy as np
        import onnx

        pixels = np.arange(24, dtype=np.float32).reshape(1, 3, 2, 4)
        parameters = [
            np.asarray(value, dtype=np.float32)
            for value in [[2, -4, 8], [3, 5, 7], [1, 2, 3], [4, 16, 64]]
        ]
        graph = expression_graph(
            pixels, parameters, 0, "paddle", [onnx.helper.make_opsetid("", 17)], 8
        )
        return pixels, graph

    def test_exact_affine_result_and_channel_broadcasting_at_both_levels(self):
        import numpy as np

        pixels, graph = self.graph()
        candidate = diagnostic.explicit_division(graph)
        expected = pixels.copy()
        expected[:, 0] += 2
        expected[:, 1] = -pixels[:, 1] + 7
        expected[:, 2] += 4
        for level in diagnostic.LEVELS:
            actual = diagnostic.session(candidate, level).run(None, {"input": pixels})[0]
            self.assertEqual(actual.tobytes(), expected.tobytes())
            self.assertEqual(actual.dtype, np.float32)

    def test_exactly_one_operation_changes_and_source_parameters_are_preserved(self):
        import onnx

        _, graph = self.graph()
        original = graph.SerializeToString()
        candidate = diagnostic.explicit_division(graph)
        self.assertEqual(graph.SerializeToString(), original)
        one = candidate.graph.initializer[-1]
        self.assertEqual(one.name, "division_one")
        self.assertEqual(onnx.numpy_helper.to_array(one).tobytes(), b"\0\0\x80\x3f")
        inverse = candidate.graph.node[2]
        self.assertEqual(inverse.op_type, "Div")
        self.assertEqual(list(inverse.input), ["division_one", "std"])
        inverse.CopyFrom(graph.graph.node[2])
        del candidate.graph.initializer[-1]
        self.assertEqual(candidate.SerializeToString(), original)

    def test_unknown_graphs_signatures_and_value_collisions_are_rejected(self):
        _, original = self.graph()
        for kind in ["opset", "structure", "signature", "collision"]:
            graph = copy.deepcopy(original)
            if kind == "opset":
                graph.opset_import[0].version = 18
            elif kind == "structure":
                graph.graph.node[0].op_type = "Sub"
            elif kind == "signature":
                graph.graph.node[2].input[0] = "variance"
            else:
                graph.graph.initializer[0].name = "division_one"
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                diagnostic.explicit_division(graph)


if __name__ == "__main__":
    unittest.main()
