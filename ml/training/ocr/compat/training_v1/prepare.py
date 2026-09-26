"""Materialize an immutable OCR dataset from reviewed references or invented smoke lines."""

import argparse
import importlib.util
import json
import shutil
from pathlib import Path

from contract import field_name, sha, validate_dataset, write
from preflight import ROOT

SOURCE = ROOT / ".local/upstream/PaddleOCR"


def prepare_smoke(output, font):
    from smoke import prepare

    prepare(output, font, SOURCE, ROOT / ".local/models/ocr/PP-OCRv6_small_rec_pretrained.pdparams")
    rows = [json.loads(line) for line in (output / "samples.jsonl").read_text().splitlines()]
    for row in rows:
        row["image"] = row["id"] + ".png"
        row["source_sha256"] = row["image_sha256"]
        fields = {
            "train": [
                "title",
                "location",
                "start_time",
                "date",
                "title",
                "start_time",
                "duration_minutes",
                "therapist",
            ],
            "validation": ["title", "location", "start_time", "date"],
        }
        row["field"] = fields[row["partition"]][int(row["id"].rsplit("-", 1)[1])]
    return {
        "schema_version": 1,
        "kind": "invented-smoke-text",
        "final_holdout": False,
        "font_sha256": sha(font),
        "samples": rows,
    }


def reference_module():
    spec = importlib.util.spec_from_file_location(
        "reference_data", ROOT / "ml/data/annotation/reference-data.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def prepare_references(output, root, fold):
    reference = reference_module()
    output.mkdir(parents=True, exist_ok=False)
    # Existing exporter checks all field approvals, crop review and frozen grouping.
    reference.export(root, output / "references", fold, 512)
    records = [
        json.loads(line)
        for line in (output / "references/recognition.jsonl").read_text().splitlines()
    ]
    rows = []
    (output / "images").mkdir()
    for record in records:
        crop = reference.materialize_line(root, record["id"], record["line_id"], 512)
        metadata = json.loads(crop.with_suffix(".json").read_text())
        if (
            metadata["text"] != record["text"]
            or metadata["reference_hash"] != record["reference_hash"]
        ):
            raise ValueError("Reviewed reference changed during materialization")
        image_hash = sha(crop)
        target = output / "images" / (image_hash + ".jpg")
        shutil.copyfile(crop, target)
        rows.append(
            {
                "id": record["id"] + "-" + record["line_id"],
                "partition": record["partition"],
                "group": record["group"],
                "variant": record["name"],
                "source_sha256": record["source_hash"],
                "image": str(target.relative_to(output)),
                "image_sha256": image_hash,
                "text": record["text"],
                "state": "legible",
                "field": field_name(metadata["lines"][0]["field"]),
                "reference_hash": record["reference_hash"],
                "crop_review_hash": sha(root / "crop-review.json"),
            }
        )
    return {
        "schema_version": 1,
        "kind": "approved-reference-crops",
        "final_holdout": False,
        "reference_export_sha256": sha(output / "references/manifest.json"),
        "source_root": str(root.resolve()),
        "samples": rows,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--smoke-font", type=Path)
    group.add_argument("--references", type=Path)
    group.add_argument("--synthetic", type=Path)
    parser.add_argument("--font", type=Path)
    parser.add_argument("--train-limit", type=int, default=512)
    parser.add_argument("--validation-limit", type=int, default=128)
    parser.add_argument("--seed", type=int, default=20260918)
    parser.add_argument("--fold", type=int, default=0)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / ".local"):
        parser.error("Prepared data must remain below .local")
    if args.fold not in range(4):
        parser.error("Development validation fold must be 0–3")
    if args.synthetic:
        from synthetic_data import prepare

        if not args.font:
            parser.error("Synthetic pixel verification requires the original --font")
        data = prepare(
            output, args.synthetic, args.font, args.train_limit, args.validation_limit, args.seed
        )
    else:
        data = (
            prepare_smoke(output, args.smoke_font)
            if args.smoke_font
            else prepare_references(output, args.references, args.fold)
        )
    write(output / "dataset.json", data)
    validate_dataset(
        output / "dataset.json",
        (SOURCE / "ppocr/utils/dict/ppocrv6_dict.txt").read_text().splitlines(),
    )
    print(json.dumps({"samples": len(data["samples"]), "kind": data["kind"], "qualified": False}))


if __name__ == "__main__":
    main()
