import importlib.util
import tempfile
import unittest
from pathlib import Path

from PIL import Image

spec = importlib.util.spec_from_file_location(
    "comparison", Path(__file__).parents[1] / "compare-screenshots.py"
)
comparison = importlib.util.module_from_spec(spec)
spec.loader.exec_module(comparison)


class ScreenshotTests(unittest.TestCase):
    def test_only_declared_system_pixels_are_excluded(self):
        with tempfile.TemporaryDirectory() as directory:
            before, after = [Path(directory) / name for name in ["before.png", "after.png"]]
            pixels = Image.new("RGB", (40, 80), "white")
            pixels.save(before)
            pixels.putpixel((10, 9), (0, 0, 0))
            pixels.save(after)
            self.assertTrue(comparison.compare(before, after, ignore_top=10)["passed"])
            pixels.putpixel((10, 10), (254, 255, 255))
            pixels.save(after)
            report = comparison.compare(before, after, ignore_top=10)
            self.assertFalse(report["passed"])
            self.assertEqual(report["different_pixels"], 1)

    def test_size_changes_and_full_image_masks_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            before, after = [Path(directory) / name for name in ["before.png", "after.png"]]
            Image.new("RGB", (40, 80)).save(before)
            Image.new("RGB", (41, 80)).save(after)
            with self.assertRaises(ValueError):
                comparison.compare(before, after)
            with self.assertRaises(ValueError):
                comparison.compare(before, before, ignore_top=80)

    def test_alpha_changes_below_the_declared_system_region_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            before, after = [Path(directory) / name for name in ["before.png", "after.png"]]
            pixels = Image.new("RGBA", (40, 80), (0, 0, 0, 255))
            pixels.save(before)
            pixels.putpixel((10, 9), (0, 0, 0, 0))
            pixels.save(after)
            self.assertTrue(comparison.compare(before, after, ignore_top=10)["passed"])
            pixels.putpixel((10, 10), (0, 0, 0, 0))
            pixels.save(after)
            report = comparison.compare(before, after, ignore_top=10)
            self.assertFalse(report["passed"])
            self.assertEqual(report["different_pixels"], 1)
            self.assertEqual(report["difference_bounds"], (10, 10, 11, 11))

    def test_opaque_rgb_and_rgba_keep_the_same_exact_result(self):
        with tempfile.TemporaryDirectory() as directory:
            before, rgb, rgba = [
                Path(directory) / name for name in ["before.png", "rgb.png", "rgba.png"]
            ]
            pixels = Image.new("RGB", (40, 80), "white")
            pixels.save(before)
            for changed in [False, True]:
                if changed:
                    pixels.putpixel((10, 10), (254, 255, 255))
                pixels.save(rgb)
                pixels.convert("RGBA").save(rgba)
                reports = [comparison.compare(before, path, ignore_top=10) for path in [rgb, rgba]]
                for report in reports:
                    self.assertEqual(report["passed"], not changed)
                    self.assertEqual(report["different_pixels"], int(changed))
                self.assertEqual(reports[0]["difference_bounds"], reports[1]["difference_bounds"])


if __name__ == "__main__":
    unittest.main()
