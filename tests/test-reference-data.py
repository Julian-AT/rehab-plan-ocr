"""Leakage, label integrity and cache checks with invented examples only."""

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


refs = load("reference-data")
synthetic = load("synthetic-plans")


def reference(i):
    h = f"{i:064x}"
    points = synthetic.rect(15, 20, 45, 20)
    a = {
        "id": f"a{i}",
        "title": "Avenor",
        "location": "Raum 107",
        "therapist": "Belvara",
        "row_polygon": points,
        "fields": {
            "title": {
                "state": "legible",
                "polygon": points,
                "confirmed_at": 1,
                "confirmed_value": "Avenor",
                "frame": "original",
            }
        },
    }
    r = {
        "schema_version": 2,
        "verified": True,
        "reviewed_at": "2030-01-01",
        "coverage_confirmed": True,
        "uncertainty_notes": [],
        "day_id": f"day-{i}",
        "split": "development",
        "document_hashes": [h],
        "sources": [
            {
                "source_hash": h,
                "original_hash": h,
                "logical_page": f"p{i}",
                "capture_series": f"c{i}",
                "treatment_days": [f"2030-01-{i + 1:02}"],
                "width": 100,
                "height": 100,
                "table_polygon": synthetic.rect(10, 10, 80, 80),
                "relationships_confirmed": True,
            }
        ],
        "appointments": [a],
        "lines": [
            {
                "id": f"l{i}",
                "source_hash": h,
                "appointment_id": a["id"],
                "field": "title",
                "text": "Avenor",
                "polygon": points,
                "state": "legible",
                "error_causes": [],
            }
        ],
    }
    a.update(date=f"2030-01-{i + 1:02}", start="08:00", end="08:30", notes="")
    for field in ["date", "start", "end", "location", "therapist", "notes"]:
        a["fields"][field] = {
            "state": "legible" if a[field] else "not_printed",
            "polygon": points,
            "frame": "original",
            "confirmed_at": 1,
            "confirmed_value": a[field],
        }
        if a[field]:
            r["lines"].append(
                {
                    "id": f"{i}-{field}",
                    "source_hash": h,
                    "appointment_id": a["id"],
                    "field": field,
                    "text": a[field],
                    "polygon": points,
                    "state": "legible",
                    "error_causes": [],
                }
            )
    r["approval_hash"] = refs.reference_hash(r)
    return r


class ReferenceDataTests(unittest.TestCase):
    def test_overlap_is_transitive_and_capture_and_page_aliases_stay_together(self):
        r = [reference(i) for i in range(8)]
        r[1]["sources"][0]["treatment_days"] = ["2030-01-01", "2030-01-02"]
        r[2]["sources"][0]["treatment_days"] = ["2030-01-02"]
        r[3]["sources"][0]["logical_page"] = "p2"
        result = refs.grouping(r)
        owner = {h: g for g, v in result["days"].items() for h in v["document_hashes"]}
        self.assertEqual(len({owner[x["document_hashes"][0]] for x in r[:4]}), 1)
        self.assertEqual(len(result["days"]), 5)
        self.assertFalse(result["final_holdout_available"])
        self.assertEqual(result, refs.grouping(list(reversed(r))))
        self.assertEqual({g["fold"] for g in result["days"].values()}, set(range(4)))

    def test_24_recipes_transform_all_polygons_and_mirror_is_orientation_only(self):
        r = reference(0)
        image = Image.new("RGB", (100, 100), "black")
        self.assertEqual(len(refs.RECIPES), 24)
        for _, recipe in refs.RECIPES:
            output, lines, m = refs.variant(image, r, recipe)
            for original, changed in zip(r["lines"][0]["polygon"], lines[0]["polygon"]):
                restored = refs.transform(refs.inverse(m), [changed])[0]
                self.assertAlmostEqual(original["x"], restored["x"])
                self.assertAlmostEqual(original["y"], restored["y"])
            self.assertEqual(output.size, refs.matrix(recipe, 100, 100)[1])
        rotated, _, _ = refs.variant(image, r, {"turn": 1})
        self.assertEqual(rotated.getpixel((0, 0)), (255, 255, 255))

    def test_obstructed_and_cut_labels_are_not_invented(self):
        r = reference(0)
        r["lines"][0]["polygon"] = synthetic.rect(75, 40, 20, 20)
        lines, _, _ = refs.variant_labels(r, {"cut": 0.78})
        self.assertEqual(lines[0]["text"], "")
        self.assertNotEqual(lines[0]["state"], "legible")
        r["lines"][0]["polygon"] = synthetic.rect(49, 45, 5, 10)
        lines, _, _ = refs.variant_labels(r, {"cover": True})
        self.assertEqual(lines[0]["state"], "illegible")
        self.assertEqual(lines[0]["text"], "")

    def test_modified_reference_and_source_relationships_block_export(self):
        r = reference(0)
        refs.approved(r)
        r["lines"][0]["polygon"][0]["x"] += 0.000001
        with self.assertRaises(ValueError):
            refs.approved(r)
        r = reference(0)
        r["sources"][0]["relationships_confirmed"] = False
        with self.assertRaises(ValueError):
            refs.grouping([r] + [reference(i) for i in range(1, 5)])

    def test_export_partitions_every_derivative_and_bounds_the_cache(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            data = [reference(i) for i in range(4)]
            split = refs.grouping(data)
            for r in data:
                r["day_id"] = next(
                    k
                    for k, g in split["days"].items()
                    if r["document_hashes"][0] in g["document_hashes"]
                )
                r["approval_hash"] = refs.reference_hash(r)
                refs.write(root / "labels/provisional" / f"{r['document_hashes'][0]}.json", r)
            refs.write(
                root / "inventory.json",
                {"entries": [{"sha256": r["document_hashes"][0]} for r in data]},
            )
            refs.write(root / "split.json", split)
            self.assertEqual(refs.export(root, root / "export", 0, 1), 96)
            records = json.loads((root / "export/manifest.json").read_text())["records"]
            by_source = {}
            for row in records:
                by_source.setdefault(row["source_hash"], set()).add(row["partition"])
            self.assertTrue(all(len(parts) == 1 for parts in by_source.values()))
            rec = [
                json.loads(v) for v in (root / "export/recognition.jsonl").read_text().splitlines()
            ]
            self.assertTrue(all("mirror" not in r["recipe"] for r in rec))
            table = next(
                json.loads(v)
                for v in (root / "export/table-assignment.jsonl").read_text().splitlines()
                if json.loads(v)["name"] == "quarter-90"
            )
            self.assertNotEqual(
                table["rows"][0]["fields"]["title"]["polygon"],
                data[0]["appointments"][0]["fields"]["title"]["polygon"],
            )
            cache = root / "cache"
            cache.mkdir()
            for n in range(3):
                (cache / f"{n}.jpg").write_bytes(b"a" * 100)
            refs.bound_cache(cache, 150)
            self.assertLessEqual(sum(p.stat().st_size for p in cache.glob("*.jpg")), 150)
            data[0]["sources"][0]["logical_page"] = "changed"
            data[0]["approval_hash"] = refs.reference_hash(data[0])
            refs.write(
                root / "labels/provisional" / f"{data[0]['document_hashes'][0]}.json",
                data[0],
            )
            with self.assertRaisesRegex(ValueError, "relationships"):
                refs.export(root, root / "stale", 0, 1)

    def test_text_crop_preserves_perspective_geometry(self):
        polygon = [
            {"x": 10, "y": 20},
            {"x": 70, "y": 30},
            {"x": 65, "y": 60},
            {"x": 5, "y": 48},
        ]
        image = Image.new("RGB", (100, 100), "white")
        crop, m = refs.line_crop(image, polygon)
        source = refs.transform(
            m,
            [
                {"x": 0, "y": 0},
                {"x": crop.width - 1, "y": 0},
                {"x": crop.width - 1, "y": crop.height - 1},
                {"x": 0, "y": crop.height - 1},
            ],
        )
        for a, b in zip(source, polygon):
            self.assertAlmostEqual(a["x"], b["x"])
            self.assertAlmostEqual(a["y"], b["y"])

    def test_synthetic_independent_combinations_and_reproducible_pixels(self):
        font = next(
            p
            for p in [
                Path("/System/Library/Fonts/Supplemental/Arial.ttf"),
                Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
            ]
            if p.exists()
        )
        a, labels = synthetic.render(4, font)
        b, again = synthetic.render(4, font)
        self.assertEqual(a.tobytes(), b.tobytes())
        self.assertEqual(labels, again)
        mappings = {}
        for i in range(12):
            _, data = synthetic.render(i, font)
            for row in data["appointments"]:
                mappings.setdefault(row["therapist"], set()).add(row["location"])
            for line in data["lines"]:
                self.assertTrue(
                    all(
                        0 <= p["x"] <= data["width"] and 0 <= p["y"] <= data["height"]
                        for p in line["polygon"]
                    )
                )
        self.assertTrue(any(len(rooms) > 3 for name, rooms in mappings.items() if name))


if __name__ == "__main__":
    unittest.main()
