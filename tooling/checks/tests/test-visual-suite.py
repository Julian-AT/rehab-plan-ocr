import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

from PIL import Image

spec = importlib.util.spec_from_file_location(
    "suite", Path(__file__).parents[1] / "compare-visual-suite.py"
)
suite = importlib.util.module_from_spec(spec)
spec.loader.exec_module(suite)


class VisualSuiteTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.baseline = self.root / "baseline"
        self.attachments = self.root / "attachments"
        self.baseline.mkdir()
        self.attachments.mkdir()
        entries, attachments = [], []
        for name in ["cards-light", "cards-dark"]:
            image = self.baseline / f"{name}.png"
            Image.new("RGB", (4, 200), "white").save(image)
            data = image.read_bytes()
            (self.attachments / image.name).write_bytes(data)
            entries.append({"file": image.name, "sha256": hashlib.sha256(data).hexdigest()})
            attachments.append(
                {
                    "exportedFileName": image.name,
                    "suggestedHumanReadableName": f"calm-{name}_0.png",
                    "isAssociatedWithFailure": False,
                }
            )
        (self.baseline / "baseline.json").write_text(json.dumps({"images": entries}))
        self.manifest = [{"attachments": attachments}]

    def compare(self):
        (self.attachments / "manifest.json").write_text(json.dumps(self.manifest))
        return suite.compare_suite(self.baseline, self.attachments, self.root / "previews")

    def test_all_references_required_without_replacing_originals(self):
        before = {p.name: p.read_bytes() for p in self.baseline.iterdir()}
        result = self.compare()
        self.assertTrue(result["passed"])
        self.assertEqual(result["matching_images"], 2)
        self.assertFalse(result["full_app_regression_qualified"])
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.baseline.iterdir()})

    def test_missing_capture_and_changed_app_pixels_fail(self):
        self.manifest[0]["attachments"].pop()
        path = self.attachments / "cards-light.png"
        with Image.open(path) as image:
            image.putpixel((1, 170), (254, 255, 255))
            image.save(path)
        result = self.compare()
        self.assertFalse(result["passed"])
        self.assertEqual(result["matching_images"], 0)

    def test_duplicate_capture_is_not_silently_selected(self):
        self.manifest[0]["attachments"] *= 2
        result = self.compare()
        self.assertFalse(result["passed"])
        self.assertTrue(all("exactly one" in r["error"] for r in result["images"]))


if __name__ == "__main__":
    unittest.main()
