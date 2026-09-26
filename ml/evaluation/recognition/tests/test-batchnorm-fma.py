"""Independent exact arithmetic and rejection controls, without model dependencies."""

import ctypes
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

DIRECTORY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DIRECTORY))
SPEC = importlib.util.spec_from_file_location("batchnorm_fma", DIRECTORY / "batchnorm_fma.py")
fma = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fma)


class ArithmeticControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temporary.cleanup)
        library = Path(cls.temporary.name) / "affine.so"
        try:
            fma.compile_reference(library)
        except FileNotFoundError as error:
            raise unittest.SkipTest("Clang is unavailable") from error
        cls.affine = staticmethod(fma.load_reference(library))

    def calculate(self, x, adjusted_scale, adjusted_bias, mean_inverse, scale, bias, mode):
        values = [
            (ctypes.c_float * 1)(v)
            for v in [x, adjusted_scale, adjusted_bias, mean_inverse, scale, bias]
        ]
        output = (ctypes.c_float * 1)(42)
        status = self.affine(*values, 1, 1, mode, output)
        return status, output[0]

    def test_output_fusion_keeps_the_product_residual(self):
        epsilon = 2**-23
        arguments = (1 + epsilon, 1 - epsilon, -1, 0, 0, -1)
        self.assertEqual(self.calculate(*arguments, 0), (0, 0))
        self.assertEqual(self.calculate(*arguments, 1), (0, -(2**-46)))

    def test_offset_fusion_is_independent_of_output_fusion(self):
        epsilon = 2**-23
        arguments = (0, 1, 0, -(1 + epsilon), 1 - epsilon, -1)
        self.assertEqual(self.calculate(*arguments, 0), (0, 0))
        self.assertEqual(self.calculate(*arguments, 1), (0, 0))
        self.assertEqual(self.calculate(*arguments, 2), (0, -(2**-46)))
        self.assertEqual(self.calculate(*arguments, 3), (0, -(2**-46)))

    def test_invalid_mode_does_not_write_output(self):
        self.assertEqual(self.calculate(1, 1, 0, 1, 1, 1, 4), (1, 42))
        self.assertEqual(self.calculate(1, 1, 0, 1, 1, 1, -1), (1, 42))

    def test_zero_or_excessive_shape_is_rejected_before_reading(self):
        value = (ctypes.c_float * 1)(42)
        for channels, plane in [(0, 1), (1, 0), (1000001, 1), (1000, 1001)]:
            self.assertEqual(self.affine(*([value] * 6), channels, plane, 0, value), 1)
            self.assertEqual(value[0], 42)


if __name__ == "__main__":
    unittest.main()
