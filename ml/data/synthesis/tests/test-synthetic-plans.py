"""Synthetic schedules must describe the pixels, not the intended layout."""

import copy
import importlib.util
import unittest
from pathlib import Path

from PIL import ImageDraw, ImageFont

SPEC = importlib.util.spec_from_file_location(
    "synthetic", Path(__file__).resolve().parents[1] / "synthetic-plans.py"
)
synthetic = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(synthetic)
FONT = next(
    p
    for p in [
        Path("/System/Library/Fonts/Supplemental/Arial.ttf"),
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
    ]
    if p.exists()
)


class SyntheticTests(unittest.TestCase):
    def test_long_unbroken_words_are_wrapped_without_losing_characters(self):
        font = ImageFont.truetype(str(FONT), 27)
        value = "ABCDEFGHIJKLMNOPQRSTUVWXYZ" * 5
        lines = synthetic.wrap(value, font, 100)
        self.assertEqual("".join(lines), value)
        self.assertGreater(len(lines), 1)
        self.assertTrue(all(font.getbbox(line)[2] - font.getbbox(line)[0] <= 100 for line in lines))

    def test_values_cannot_diverge_from_the_printed_evidence(self):
        image, labels = synthetic.render(4, FONT)
        changed = copy.deepcopy(labels)
        changed["appointments"][0]["title"] = "Nicht gedruckte Behandlung"
        with self.assertRaises(ValueError):
            synthetic.validate(image, changed, FONT)
        changed = copy.deepcopy(labels)
        duplicate = dict(changed["lines"][0], id="duplicate")
        changed["lines"].append(duplicate)
        with self.assertRaises(ValueError):
            synthetic.validate(image, changed, FONT)

    def test_shared_heading_is_drawn_and_labeled_once(self):
        _, labels = synthetic.render(4, FONT)
        dates = [line for line in labels["lines"] if line["field"] == "date"]
        self.assertEqual(len(dates), len({row["date"] for row in labels["appointments"]}))
        self.assertEqual(len({line["id"] for line in labels["lines"]}), len(labels["lines"]))

    def test_pixel_validation_rejects_covered_or_clipped_complete_labels(self):
        image, labels = synthetic.render(4, FONT)
        synthetic.validate(image, labels, FONT)
        covered = image.copy()
        line = next(line for line in labels["lines"] if line["field"] == "title")
        polygon = line["polygon"]
        ImageDraw.Draw(covered).rectangle(
            (polygon[0]["x"], polygon[0]["y"], polygon[2]["x"], polygon[2]["y"]), fill="white"
        )
        with self.assertRaises(ValueError):
            synthetic.validate(covered, labels, FONT)
        with self.assertRaises(ValueError):
            synthetic.validate(image.crop((0, 0, image.width // 2, image.height)), labels, FONT)

    def test_multiple_days_blank_fields_and_negative_inputs_are_explicit(self):
        kinds, arrangements, day_counts = set(), set(), set()
        blanks = 0
        for index in range(20):
            image, labels = synthetic.render(index, FONT)
            synthetic.validate(image, labels, FONT)
            kinds.add(labels["input_kind"])
            arrangements.add(tuple(labels["column_order"]))
            day_counts.add(len(labels["days"]))
            for row in labels["appointments"]:
                for name, field in row["fields"].items():
                    if not row[name]:
                        blanks += 1
                        self.assertEqual(field["state"], "not_printed")
                        self.assertEqual(field["line_ids"], [])
            if labels["input_kind"] != "schedule":
                self.assertEqual(labels["appointments"], [])
        self.assertEqual(kinds, {"schedule", "non_plan", "unusable"})
        self.assertIn(2, day_counts)
        self.assertGreater(len(arrangements), 1)
        self.assertGreater(blanks, 0)


if __name__ == "__main__":
    unittest.main()
