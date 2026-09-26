"""Geometry, privacy masking and unavailable-label tests use invented pixels only."""

import sys
import unittest
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import variants  # noqa: E402


def rect(x, y, width, height):
    return [
        {"x": x, "y": y},
        {"x": x + width, "y": y},
        {"x": x + width, "y": y + height},
        {"x": x, "y": y + height},
    ]


def reference(polygons=None):
    return {
        "sources": [
            {
                "source_hash": "invented",
                "width": 100,
                "height": 100,
                "table_polygon": rect(0, 0, 100, 100),
            }
        ],
        "appointments": [{"row_polygon": rect(10, 20, 80, 20)}],
        "lines": [
            {"id": str(i), "polygon": p, "state": "legible", "text": "Erfunden"}
            for i, p in enumerate(polygons or [rect(40, 20, 20, 20)])
        ],
    }


class VariantTests(unittest.TestCase):
    def test_mismatched_source_dimensions_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "dimensions"):
            variants.variant(Image.new("RGB", (80, 100)), reference(), {})

    def test_clipping_drops_zero_area_and_fully_invisible_polygons(self):
        self.assertEqual(variants.clip(rect(100, 20, 10, 10), (100, 100)), [])
        self.assertEqual(variants.clip(rect(110, 20, 10, 10), (100, 100)), [])
        clipped = variants.clip(rect(90, 20, 20, 10), (100, 100))
        self.assertEqual(len(clipped), 4)
        self.assertTrue(all(0 <= p["x"] <= 100 and 0 <= p["y"] <= 100 for p in clipped))

    def test_compound_rotation_scale_crop_matches_pixels_and_inverse(self):
        image = Image.new("RGB", (100, 100), "white")
        ImageDraw.Draw(image).rectangle((40, 20, 59, 39), fill="black")
        recipe = {"turn": 1, "scale": 0.5, "crop": [0.1, 0.2, 0.1, 0.1]}
        output, lines, matrix = variants.variant(image, reference(), recipe)
        self.assertEqual(output.size, (40, 35))
        point = variants.transform(matrix, [{"x": 50, "y": 30}])[0]
        self.assertEqual(point, {"x": 30, "y": 15})
        self.assertLess(max(output.getpixel((30, 15))), 10)
        self.assertEqual(lines[0]["state"], "legible")
        for original, changed in zip(reference()["lines"][0]["polygon"], lines[0]["polygon"]):
            restored = variants.transform(variants.inverse(matrix), [changed])[0]
            self.assertAlmostEqual(original["x"], restored["x"])
            self.assertAlmostEqual(original["y"], restored["y"])

    def test_combined_cut_cover_and_glare_remove_every_affected_target(self):
        ref = reference(
            [rect(80, 10, 10, 10), rect(49, 45, 7, 12), rect(10, 10, 10, 10), rect(20, 75, 10, 10)]
        )
        recipe = {"cut": 0.78, "cover": True, "glare": [0, 0, 0.25, 0.25]}
        output, lines, _ = variants.variant(Image.new("RGB", (100, 100), "black"), ref, recipe)
        self.assertEqual(
            [line["state"] for line in lines], ["cropped", "illegible", "illegible", "legible"]
        )
        self.assertTrue(all(line["text"] == "" for line in lines[:3]))
        for point in [(85, 15), (51, 50), (15, 15)]:
            self.assertEqual(output.getpixel(point), (255, 255, 255))

    def test_blank_cropped_fields_are_unknown_and_retain_source_state(self):
        ref = reference()
        recipe = {"crop": [0, 0, 0.25, 0]}
        matrix, size = variants.matrix(recipe, 100, 100)
        field = variants.field_label(
            {"state": "not_printed", "polygon": rect(85, 20, 10, 20)},
            [],
            ref["sources"][0],
            recipe,
            matrix,
            size,
        )
        self.assertEqual(field["state"], "cropped")
        self.assertEqual(field["source_state"], "not_printed")
        self.assertEqual(field["visible_polygon"], [])

    def test_masked_header_cannot_keep_a_complete_training_label(self):
        ref = reference([rect(20, 5, 30, 12), rect(20, 30, 30, 12)])
        ref["sources"][0]["table_polygon"] = rect(10, 20, 80, 70)
        output, lines, _ = variants.variant(Image.new("RGB", (100, 100), "black"), ref, {})
        self.assertEqual(output.getpixel((30, 10)), (255, 255, 255))
        self.assertEqual(lines[0]["state"], "cropped")
        self.assertEqual(lines[0]["text"], "")
        self.assertEqual(lines[1]["text"], "Erfunden")

    def test_noise_tint_and_colored_rows_are_reproducible(self):
        image = Image.new("RGB", (100, 100), "white")
        recipe = {"noise": 15, "tint": [240, 230, 220], "row_tint": True}
        first, lines, matrix = variants.variant(image, reference(), recipe)
        second, again, repeated = variants.variant(image, reference(), recipe)
        self.assertEqual(first.tobytes(), second.tobytes())
        self.assertEqual((lines, matrix), (again, repeated))
        self.assertNotEqual(first.tobytes(), image.tobytes())

    def test_severe_resolution_loss_has_no_full_text_target(self):
        lines, _, _ = variants.variant_labels(reference(), {"scale": 0.2})
        self.assertEqual(lines[0]["state"], "illegible")
        self.assertEqual(lines[0]["text"], "")

    def test_concave_mask_checks_crossing_edges_not_only_corners(self):
        boundary = [
            {"x": x, "y": y}
            for x, y in [
                (0, 0),
                (100, 0),
                (100, 100),
                (60, 100),
                (60, 40),
                (40, 40),
                (40, 100),
                (0, 100),
            ]
        ]
        self.assertFalse(variants.inside(rect(20, 20, 60, 60), boundary))
        self.assertTrue(variants.inside(rect(5, 5, 20, 20), boundary))


if __name__ == "__main__":
    unittest.main()
