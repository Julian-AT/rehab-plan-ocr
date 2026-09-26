"""Independent arithmetic/rejection controls; no model, NumPy or runtime needed."""

import ctypes
import importlib.util
import platform
import struct
import sys
import tempfile
import unittest
from pathlib import Path

DIRECTORY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DIRECTORY))
SPEC = importlib.util.spec_from_file_location("reciprocal", DIRECTORY / "batchnorm_reciprocal.py")
reciprocal = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(reciprocal)


@unittest.skipUnless(platform.machine() in {"arm64", "aarch64"}, "ARM64 arithmetic required")
class ArithmeticControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temporary.cleanup)
        library = Path(cls.temporary.name) / "reciprocal.so"
        # A tiny wrapper changes the real thread's rounding mode and restores it.
        source = Path(cls.temporary.name) / "rounding.cpp"
        source.write_text(
            reciprocal.CPP.read_text()
            + """
extern "C" int reject_upward_rounding() {
    const int previous = std::fegetround();
    if (std::fesetround(FE_UPWARD)) return -1;
    float values[4] = {1, 1, 1, 1};
    float coefficients[16];
    float output[4] = {42, 42, 42, 42};
    const int status = batchnorm_reciprocal(values, values, values, values,
        values, 0, 4, 1, 0, coefficients, output);
    const int restored = std::fesetround(previous);
    return status == 1 && output[0] == 42 && restored == 0 ? 0 : -1;
}
"""
        )
        try:
            reciprocal.compile_reference(library, source)
        except FileNotFoundError as error:
            raise unittest.SkipTest("Clang is unavailable") from error
        cls.calculate = staticmethod(reciprocal.load_reference(library))
        cls.reject_upward = staticmethod(ctypes.CDLL(str(library)).reject_upward_rounding)

    def values(self, **changes):
        values = {
            "input": [1, 2, 3, 4, 5, 6, 7, 8],
            "scale": [2, -4, 3, 8],
            "bias": [1, 2, 3, 4],
            "mean": [2, 4, 1, 8],
            "variance": [4, 16, 1, 64],
        } | changes
        return [(ctypes.c_float * len(value))(*value) for value in values.values()]

    def run_case(self, values=None, epsilon=0, mode=0, channels=4, plane=2):
        coefficients = (ctypes.c_float * 16)(*([42] * 16))
        output = (ctypes.c_float * 8)(*([42] * 8))
        status = self.calculate(
            *(values if values is not None else self.values()),
            epsilon,
            channels,
            plane,
            mode,
            coefficients,
            output,
        )
        return status, list(coefficients), list(output)

    def assert_rejected(self, **arguments):
        self.assertEqual(self.run_case(**arguments), (1, [42] * 16, [42] * 8))

    def test_exact_channel_arithmetic_and_layout(self):
        # Powers of two make every expected coefficient exact, independently of either mode.
        expected = [0.5, 0.25, 1, 0.125, 1, -1, 3, 1, 1, 1, 1, 1, -1, 6, 0, -4]
        for mode in [0, 1]:
            self.assertEqual(self.run_case(mode=mode), (0, expected, [0, 1, 3, 2, 15, 18, 3, 4]))

    def test_hardware_division_rounds_a_nonbinary_fraction(self):
        # sqrt(9) is exact; the nearest FP32 value of 1/3 has bits 0x3eaaaaab.
        result = self.run_case(values=self.values(variance=[9] * 4), mode=1)
        self.assertEqual(result[0], 0)
        self.assertEqual(struct.pack("=f", result[1][0]), struct.pack("=I", 0x3EAAAAAB))

    def test_epsilon_is_added_before_square_root(self):
        for mode in [0, 1]:
            result = self.run_case(values=self.values(variance=[0] * 4), epsilon=4, mode=mode)
            self.assertEqual(result[0], 0)
            self.assertEqual(result[1][:4], [0.5] * 4)

    def test_final_multiplication_is_not_contracted(self):
        epsilon = 2**-23
        values = self.values(
            input=[1 + epsilon] * 8,
            scale=[1 - epsilon] * 4,
            bias=[-1] * 4,
            mean=[0] * 4,
            variance=[1] * 4,
        )
        for mode in [0, 1]:
            self.assertEqual(self.run_case(values=values, mode=mode)[2], [0] * 8)

    def test_shape_mode_and_null_are_rejected_before_reading(self):
        for channels, plane in [(0, 2), (3, 2), (4, 0), (1000004, 1), (4, 250001)]:
            self.assert_rejected(channels=channels, plane=plane)
        for mode in [-1, 2]:
            self.assert_rejected(mode=mode)
        values = self.values()
        values[0] = None
        self.assert_rejected(values=values)

    def test_invalid_numbers_do_not_modify_destinations(self):
        for value in [float("nan"), float("inf"), 2**-149]:
            self.assert_rejected(values=self.values(input=[value] + [1] * 7))
            self.assert_rejected(epsilon=value)
        for variance in [-1, 0, float("inf")]:
            self.assert_rejected(values=self.values(variance=[variance] * 4))
        self.assert_rejected(epsilon=-1)

    def test_different_rounding_mode_is_rejected_and_restored(self):
        self.assertEqual(self.reject_upward(), 0)
        self.assertEqual(self.run_case()[0], 0)


if __name__ == "__main__":
    unittest.main()
