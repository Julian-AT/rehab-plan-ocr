"""Prepare grouped, pixel-verified synthetic schedule crops without reference approval."""

import hashlib
import importlib.util
import io
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

from contract import CRITICAL, digest, field_name, sha
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[3]
GENERATOR = ROOT / "ml/data/synthesis/synthetic-plans.py"
REQUIRED_FIELDS = {"date", "start_time", "end_time", "title", "location", "therapist", "notes"}


def legacy_adapter():
    """Replay the frozen v2 contract; never rewrite old run identities or receipts."""
    path = Path(__file__).with_name("compat") / "synthetic_data_v1.py"
    spec = importlib.util.spec_from_file_location("ocr_synthetic_adapter_v1", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.ROOT = ROOT
    module.GENERATOR = ROOT / "ml/data/synthesis/compat/synthetic_plans_v2.py"
    return module


def generator():
    spec = importlib.util.spec_from_file_location("ocr_synthetic_generator", GENERATOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def select(rows, limit, seed):
    """Balance fields without inspecting recognition results."""
    by_field = defaultdict(list)
    for row in sorted(rows, key=lambda row: digest([seed, row["id"]])):
        by_field[row["field"]].append(row)
    chosen = []
    while len(chosen) < limit and any(by_field.values()):
        for field in sorted(by_field):
            if by_field[field] and len(chosen) < limit:
                chosen.append(by_field[field].pop())
    return chosen


def coverage_report(rows, selected, minimum_per_field=None):
    """Novel means absent from every training-source field, including unselected crops."""
    coverage = {}
    train_texts = {r["text"] for r in rows if r["partition"] == "train"}
    for partition in ["train", "validation"]:
        minimum = (minimum_per_field or {}).get(partition, 1)
        chosen = [r for r in selected if r["partition"] == partition]
        fields = {}
        for field in sorted(REQUIRED_FIELDS):
            samples = [r for r in chosen if r["field"] == field]
            if not samples:
                raise ValueError(f"Synthetic {partition} coverage missing field: {field}")
            if len(samples) < minimum:
                raise ValueError(
                    f"Synthetic {partition} coverage below minimum {minimum} for {field}"
                )
            texts = {r["text"] for r in samples}
            novel = texts - train_texts
            if partition == "validation" and field in {"title", "location", "notes"} and not novel:
                raise ValueError(f"Synthetic validation has no unseen text for {field}")
            fields[field] = {
                "samples": len(samples),
                "groups": len({r["group"] for r in samples}),
                "distinct_texts": len(texts),
                "unseen_in_training_source": len(novel),
            }
        coverage[partition] = {
            "samples": len(chosen),
            "groups": len({r["group"] for r in chosen}),
            "minimum_per_field": minimum,
            "fields": fields,
        }
    return coverage


def build(source, font, train_limit=512, validation_limit=128, seed=20260918):
    if any(type(n) is not int or n < 1 for n in [train_limit, validation_limit]):
        raise ValueError("Positive crop limits required")
    source, font = source.resolve(strict=True), font.resolve(strict=True)
    manifest_path = source / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    if manifest.get("schema_version") == 2:
        return legacy_adapter().build(source, font, train_limit, validation_limit, seed)
    renderer = generator()
    if (
        manifest.get("schema_version") != renderer.VERSION
        or manifest.get("synthetic") is not True
        or manifest.get("purpose") != "training_and_robustness_only"
        or manifest.get("generator_sha256") != sha(GENERATOR)
        or manifest.get("font_sha256") != sha(font)
        or manifest.get("count") != len(manifest["records"])
    ):
        raise ValueError("Synthetic generator, font or source manifest changed")
    if manifest.get("partition_seed") != seed:
        raise ValueError("Development partitions must retain their pre-rendering seed")
    rows, crops, seen, groups, kinds = [], {}, set(), {}, Counter()
    for record in manifest["records"]:
        identifier = record["id"]
        if not re.fullmatch(r"plan-[0-9]+", identifier) or identifier in seen:
            raise ValueError("Unique local synthetic source IDs required")
        seen.add(identifier)
        paths = [source / f"{identifier}.{extension}" for extension in ["png", "json"]]
        if any(p.is_symlink() or not p.is_file() for p in paths) or any(
            sha(p) != record[key]
            for p, key in zip(paths, ["image_sha256", "labels_sha256"], strict=True)
        ):
            raise ValueError("Synthetic source pixels or labels changed")
        labels = json.loads(paths[1].read_text())
        if (
            labels.get("synthetic") is not True
            or labels.get("independent_final_test") is not False
            or labels.get("group") != record["group"]
            or labels.get("input_kind") != record["input_kind"]
            or labels.get("seed") != record["seed"]
            or labels.get("image_file") != paths[0].name
            or labels.get("image_sha256") != record["image_sha256"]
            or labels.get("partition") != record.get("partition")
            or labels.get("partition_seed") != seed
            or labels.get("vocabulary") != record.get("partition")
        ):
            raise ValueError("Synthetic source lineage differs from its manifest")
        group = record["group"]
        # Freeze whole generated documents before selecting any crop or derivative.
        partition = "validation" if int(digest([seed, group]), 16) % 5 == 0 else "train"
        if partition != labels["partition"]:
            raise ValueError("Development partition changed after rendering")
        groups[group] = partition
        kinds[record["input_kind"]] += 1
        with Image.open(paths[0]) as decoded:
            image = decoded.convert("RGB")
        renderer.validate(image, labels, font)
        if labels["input_kind"] != "schedule":
            continue  # Negative/unusable inputs have no positive recognition target.
        for line in labels["lines"]:
            if line["field"] not in CRITICAL | {"start", "end", "notes"}:
                continue
            crop = ImageOps.expand(
                image.crop(renderer.bounds(line["polygon"])), border=4, fill=line["background"]
            )
            buffer = io.BytesIO()
            crop.save(buffer, format="PNG")
            pixels = buffer.getvalue()
            image_hash = hashlib.sha256(pixels).hexdigest()
            crops[image_hash] = pixels
            rows.append(
                {
                    "id": identifier + ":" + line["id"],
                    "partition": partition,
                    "group": group,
                    "variant": "original",
                    "source_sha256": record["image_sha256"],
                    "labels_sha256": record["labels_sha256"],
                    "image": "images/" + image_hash + ".png",
                    "image_sha256": image_hash,
                    "text": line["text"],
                    "state": line["state"],
                    "field": field_name(line["field"]),
                    "source_polygon": line["polygon"],
                }
            )
    labels_by_pixels = defaultdict(set)
    for row in rows:
        labels_by_pixels[row["image_sha256"]].add(row["text"])
    if any(len(values) != 1 for values in labels_by_pixels.values()):
        raise ValueError("Identical pixels have contradictory recognition labels")
    train_pixels = {row["image_sha256"] for row in rows if row["partition"] == "train"}
    # Repeated printed strings can produce identical crops on unrelated tables.
    # Remove all such validation copies before selection, never move their pages.
    excluded = [
        row
        for row in rows
        if row["partition"] == "validation" and row["image_sha256"] in train_pixels
    ]
    excluded_ids = {row["id"] for row in excluded}
    eligible = [row for row in rows if row["id"] not in excluded_ids]
    selected = [
        row
        for partition, limit in [("train", train_limit), ("validation", validation_limit)]
        for row in select([r for r in eligible if r["partition"] == partition], limit, seed)
    ]
    if {row["partition"] for row in selected} != {"train", "validation"}:
        raise ValueError("Synthetic sources need nonempty distinct development partitions")
    coverage = coverage_report(
        rows,
        selected,
        {
            "train": max(1, train_limit // len(REQUIRED_FIELDS)),
            "validation": max(1, validation_limit // len(REQUIRED_FIELDS)),
        },
    )
    return {
        "schema_version": 1,
        "kind": "pixel-verified-synthetic-crops",
        "final_holdout": False,
        "qualified": False,
        "preparation": {
            "source_root": str(source),
            "source_manifest_sha256": sha(manifest_path),
            "font": str(font),
            "font_sha256": sha(font),
            "generator_sha256": sha(GENERATOR),
            "adapter_sha256": sha(Path(__file__)),
            "train_limit": train_limit,
            "validation_limit": validation_limit,
            "seed": seed,
            "padding_pixels": 4,
        },
        "source_groups": groups,
        "input_counts": dict(kinds),
        "available_crops": len(rows),
        "excluded_validation_duplicate_crops": len(excluded),
        "coverage": coverage,
        "samples": selected,
    }, crops


def prepare(output, source, font, train_limit, validation_limit, seed):
    dataset, crops = build(source, font, train_limit, validation_limit, seed)
    output.mkdir(parents=True, exist_ok=False)
    (output / "images").mkdir()
    for row in dataset["samples"]:
        (output / row["image"]).write_bytes(crops[row["image_sha256"]])
    return dataset


def verify(dataset):
    provenance = dataset["preparation"]
    expected, _ = build(
        Path(provenance["source_root"]),
        Path(provenance["font"]),
        provenance["train_limit"],
        provenance["validation_limit"],
        provenance["seed"],
    )
    if dataset != expected:
        raise ValueError("Synthetic samples, labels, grouping or preparation lineage changed")
