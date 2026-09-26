"""Render and repeat every recipe on verified invented sources; never approve real data."""

import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(source, output, font, limit):
    synthetic_path = ROOT / "ml/data/synthesis/synthetic-plans.py"
    synthetic = load("synthetic", synthetic_path)
    refs = load("references", ROOT / "ml/data/annotation/reference-data.py")
    manifest = json.loads((source / "manifest.json").read_text())
    if (
        manifest.get("synthetic") is not True
        or manifest.get("schema_version") != 2
        or manifest.get("generator_sha256") != sha(synthetic_path)
    ):
        raise ValueError("Use a current verified synthetic generator export")
    if not 1 <= limit <= len(manifest["records"]) or sha(font) != manifest["font_sha256"]:
        raise ValueError("Source count or font differs from the synthetic export")
    output.mkdir(parents=True, exist_ok=False)
    generator = refs.augmentation_identity()
    records = []
    for entry in manifest["records"][:limit]:
        name = entry["id"]
        if Path(name).name != name or name in {"", ".", ".."}:
            raise ValueError("Invalid synthetic source filename")
        image_path, labels_path = source / f"{name}.png", source / f"{name}.json"
        for path, expected in [
            (image_path, entry["image_sha256"]),
            (labels_path, entry["labels_sha256"]),
        ]:
            if not path.resolve().is_relative_to(source.resolve()) or sha(path) != expected:
                raise ValueError("Synthetic source changed or escapes its dataset")
        labels = json.loads(labels_path.read_text())
        with Image.open(image_path) as opened:
            image = opened.convert("RGB")
        synthetic.validate(image, labels, font)
        reference = {
            "sources": [
                {
                    "source_hash": entry["image_sha256"],
                    "width": image.width,
                    "height": image.height,
                    "table_polygon": synthetic.rect(0, 0, image.width, image.height),
                }
            ],
            "lines": labels["lines"],
            "appointments": labels["appointments"],
        }
        for recipe_name, recipe in refs.RECIPES:
            rendered, lines, matrix = refs.variant(image, reference, recipe)
            repeated, other_lines, other_matrix = refs.variant(image, reference, recipe)
            if rendered.tobytes() != repeated.tobytes() or (lines, matrix) != (
                other_lines,
                other_matrix,
            ):
                raise ValueError("Augmentation pixels or geometry are not reproducible")
            if any(line["text"] for line in lines if line["state"] != "legible"):
                raise ValueError("Unavailable text retained a complete training target")
            path = output / f"{name}-{recipe_name}.jpg"
            quality = recipe.get("quality", 92)
            rendered.save(path, quality=quality)
            check = io.BytesIO()
            repeated.save(check, format="JPEG", quality=quality)
            if path.read_bytes() != check.getvalue():
                raise ValueError("Encoded augmentation is not reproducible")
            records.append(
                {
                    "source": name,
                    "group": entry["group"],
                    "recipe": recipe_name,
                    "image_sha256": sha(path),
                    "labels_sha256": refs.digest(lines),
                    "unavailable_lines": sum(line["state"] != "legible" for line in lines),
                    "legible_lines": sum(line["state"] == "legible" for line in lines),
                    "recognition_eligible": "mirror" not in recipe,
                }
            )
    if refs.augmentation_identity() != generator:
        raise ValueError("Augmentation source changed during verification")
    report = {
        "schema_version": 1,
        "purpose": "synthetic_recipe_verification_only",
        "augmentation_version": refs.AUGMENTATION_VERSION,
        "source_manifest_sha256": sha(source / "manifest.json"),
        "generator_sha256": generator,
        "verifier_sha256": sha(Path(__file__)),
        "sources": limit,
        "recipes_per_source": len(refs.RECIPES),
        "repeat_equal": True,
        "real_references_approved": False,
        "records": records,
    }
    (output / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"sources": limit, "variants": len(records), "repeat_equal": True}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--font", required=True, type=Path)
    parser.add_argument("--limit", type=int, default=2)
    args = parser.parse_args()
    verify(args.source, args.output, args.font, args.limit)
