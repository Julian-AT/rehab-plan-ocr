"""Private-image tooling checks with invented temporary images only.

Run: uv run --with pillow==12.1.1 --with pillow-heif==1.7.0 python tests/test-image-tools.py
"""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


converter = load("convert-images")
checker = load("check-images")


class ConversionTests(unittest.TestCase):
    def test_heic_duplicates_preserve_all_originals_and_existing_png(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            image = Image.new("RGB", (32, 48), (110, 120, 130))
            exif = Image.Exif()
            exif[315] = "Invented private author"
            image.save(source / "photo.HEIC", format="HEIF", exif=exif)
            (source / "photo-copy.HEIC").write_bytes(
                (source / "photo.HEIC").read_bytes()
            )
            image.save(source / "photo.png")
            originals = {p.name: converter.digest(p) for p in source.iterdir()}
            output = root / "converted"
            result = converter.prepare(source, output)
            self.assertEqual((result["source_count"], result["unique_count"]), (2, 1))
            self.assertEqual(len(result["entries"][0]["sources"]), 2)
            self.assertEqual(
                originals, {p.name: converter.digest(p) for p in source.iterdir()}
            )
            with Image.open(output / "photo.png") as converted:
                self.assertEqual(converted.size, (32, 48))
                self.assertFalse(converted.getexif())
                self.assertNotIn("xmp", converted.info)
            with self.assertRaises(FileExistsError):
                converter.prepare(source, output)

    def test_orientation_applied_once_and_metadata_removed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            image = Image.new("RGB", (40, 20), "red")
            image.paste("blue", (20, 0, 40, 20))
            exif = Image.Exif()
            exif[274] = 6
            exif[315] = "Private metadata"
            image.save(root / "rotated.jpg", quality=100, subsampling=0, exif=exif)
            converter.convert(root / "rotated.jpg", root / "upright.png")
            with Image.open(root / "upright.png") as upright:
                self.assertEqual(upright.size, (20, 40))
                self.assertGreater(upright.getpixel((10, 5))[0], 240)
                self.assertGreater(upright.getpixel((10, 35))[2], 240)
                self.assertFalse(upright.getexif())

    def test_same_stem_in_subdirectories_does_not_overwrite(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            for name, color in (("a", "red"), ("b", "blue")):
                (source / name).mkdir(parents=True)
                Image.new("RGB", (16, 16), color).save(source / name / "photo.heic")
            result = converter.prepare(source, root / "converted")
            paths = {e["png"]["path"] for e in result["entries"]}
            self.assertEqual(len(paths), 2)
            self.assertTrue(all(Path(p).exists() for p in paths))


class ReportTests(unittest.TestCase):
    def test_diagnostics_preserve_duplicate_appointments(self):
        run = json.loads((ROOT / "tests/fixtures/sample-run.json").read_text())
        result = checker.summarize(run)
        self.assertEqual(result["appointments"], 8)
        self.assertEqual(result["missing_end_or_duration"], 1)
        self.assertEqual(result["missing_date"], 0)
        self.assertNotIn("accuracy", result)

    def test_private_html_escapes_recognized_markup(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            destination = output / "document-01"
            destination.mkdir()
            run = json.loads((ROOT / "tests/fixtures/sample-run.json").read_text())
            run["appointments"][0]["title"] = (
                '<script src="https://example.invalid"></script>'
            )
            checker.write_json(destination / "run.json", run)
            checker.review_html(
                output,
                [
                    {
                        "id": "document-01",
                        "filename": "invented.png",
                        "status": "complete",
                        "diagnostics": checker.summarize(run),
                    }
                ],
            )
            report = (output / "review.html").read_text()
            self.assertNotIn("<script", report)
            self.assertIn("&lt;script", report)
            self.assertIn("Unverified predictions", report)
            self.assertIn("Content-Security-Policy", report)


if __name__ == "__main__":
    unittest.main()
