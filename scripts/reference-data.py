# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow==12.1.0"]
# ///
"""Local, provenance-preserving reference exports and deterministic variants.

Real examples require explicit reference and relationship approval. Recipes are
versioned; derived pixels live in a size-bounded cache. No network or training.
"""

import argparse
import hashlib
import json
import math
import sqlite3
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageOps

VERSION = 2
SEED = "reha-development-folds-v2"
RECIPES = [
    ("original", {}),
    ("quarter-90", {"turn": 1}),
    ("quarter-180", {"turn": 2}),
    ("quarter-270", {"turn": 3}),
    ("skew-minus3", {"angle": -3}),
    ("skew-plus3", {"angle": 3}),
    ("skew-minus7", {"angle": -7}),
    ("skew-plus7", {"angle": 7}),
    ("perspective-left", {"perspective": -0.08}),
    ("perspective-right", {"perspective": 0.08}),
    ("shadow-left", {"shadow": -1}),
    ("shadow-right", {"shadow": 1}),
    ("dim", {"brightness": 0.7}),
    ("bright", {"brightness": 1.2}),
    ("low-contrast", {"contrast": 0.65}),
    ("high-contrast", {"contrast": 1.3}),
    ("blur-light", {"blur": 0.6}),
    ("blur-medium", {"blur": 1.1}),
    ("compression", {"quality": 55}),
    ("resolution", {"scale": 0.6}),
    ("mirror-horizontal", {"mirror": "horizontal"}),
    ("mirror-vertical", {"mirror": "vertical"}),
    ("cut-right-column", {"cut": 0.78}),
    ("covered-characters", {"cover": True}),
]


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def file_hash(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".part")
    temp.write_bytes(json.dumps(value, ensure_ascii=False, indent=2).encode() + b"\n")
    temp.replace(path)


def normalized_numbers(value):
    if isinstance(value, bool) or value is None:
        return value
    if isinstance(value, (float, int)):
        return {"$f64": struct.pack(">d", float(value)).hex()}
    if isinstance(value, list):
        return [normalized_numbers(v) for v in value]
    if isinstance(value, dict):
        return {k: normalized_numbers(v) for k, v in value.items()}
    return value


def reference_hash(ref):
    return digest(
        normalized_numbers(
            {
                k: v
                for k, v in ref.items()
                if k not in {"verified", "reviewed_at", "content_hash", "approval_hash"}
            }
        )
    )


def crop_hash(line):
    return digest(
        normalized_numbers({k: line[k] for k in ["id", "source_hash", "text", "polygon", "state"]})
    )


def reviewed_crops(root, references):
    """Field truth does not certify that a training crop contains every glyph."""
    path = root / "crop-review.json"
    if not path.exists():
        return set()
    review = json.loads(path.read_text())
    lines = {line["id"]: line for ref in references for line in ref["lines"]}
    approved = review.get("lines", {})
    if approved and (review.get("schema_version") != 1 or not review.get("reviewed_at")):
        raise ValueError("Training crop review needs a version and review timestamp.")
    for identifier, digest_value in approved.items():
        if identifier not in lines or crop_hash(lines[identifier]) != digest_value:
            raise ValueError("Training crop changed after its separate visual review.")
    return set(approved)


def approved(ref):
    kind = ref.get("input_class", "rehabilitation_plan")
    if kind not in {"rehabilitation_plan", "non_plan", "unusable"}:
        raise ValueError("Unknown reference input class.")
    if kind == "non_plan" and ref.get("appointments"):
        raise ValueError("Non-plan reference contains appointments.")
    if (
        ref.get("schema_version") != VERSION
        or not ref.get("verified")
        or not ref.get("coverage_confirmed")
        or not ref.get("reviewed_at")
        or ref.get("uncertainty_notes")
        or ref.get("approval_hash") != reference_hash(ref)
    ):
        raise ValueError("Reference is unapproved or changed after approval.")
    if len(ref.get("sources", [])) != 1 or (
        not ref.get("appointments") and kind == "rehabilitation_plan"
    ):
        raise ValueError("Exactly one original and a complete row inventory required.")
    for a in ref["appointments"]:
        for field in [
            "date",
            "start",
            "end",
            "title",
            "location",
            "therapist",
            "notes",
        ]:
            f = a.get("fields", {}).get(field, {})
            if (
                f.get("state", "unreviewed") == "unreviewed"
                or f.get("confirmed_at") is None
                or f.get("confirmed_value") != a.get(field)
            ):
                raise ValueError("Every field and its printed state must be confirmed.")
            if f["state"] == "not_printed" and a.get(field):
                raise ValueError("Not-printed fields cannot contain invented labels.")
            if f["state"] == "legible" and not any(
                line["appointment_id"] == a["id"]
                and line["field"] == field
                and line["state"] == "legible"
                and line["text"]
                for line in ref["lines"]
            ):
                raise ValueError("Printed text requires source-linked line polygons.")


def grouping(references):
    """Transitive closure: overlapping days, original bytes, pages and series."""
    sources = [s for r in references for s in r["sources"]]
    if any(
        not s.get("relationships_confirmed")
        or not s["treatment_days"]
        or not s["logical_page"]
        or not s["capture_series"]
        for s in sources
    ):
        raise ValueError("Confirm every page, capture series and treatment day before splitting.")
    parents = list(range(len(sources)))

    def root(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i

    for i, a in enumerate(sources):
        for j, b in enumerate(sources[:i]):
            if set(a["treatment_days"]) & set(b["treatment_days"]) or any(
                a[k] == b[k]
                for k in (
                    "source_hash",
                    "original_hash",
                    "logical_page",
                    "capture_series",
                )
            ):
                parents[root(i)] = root(j)
    groups = {}
    for i, source in enumerate(sources):
        groups.setdefault(root(i), []).append(source)
    groups = sorted(
        groups.values(),
        key=lambda g: digest([SEED, sorted(s["original_hash"] for s in g)]),
    )
    if len(groups) < 4:
        raise ValueError(
            "Four independent development groups required; never split overlapping pages to reach four."
        )
    return {
        "schema_version": 3,
        "seed": SEED,
        "kind": "previously_explored_development",
        "grouping_verified": True,
        "final_holdout_available": False,
        "relationships_hash": digest(
            normalized_numbers(sorted(sources, key=lambda s: s["source_hash"]))
        ),
        "days": {
            f"development-{i + 1:02}": {
                "split": "development",
                "fold": i % 4,
                "grouping_verified": True,
                "document_hashes": sorted(s["source_hash"] for s in g),
                "treatment_days": sorted({d for s in g for d in s["treatment_days"]}),
                "captures": [
                    {
                        "id": s["capture_series"],
                        "pages": {s["logical_page"]: s["source_hash"]},
                    }
                    for s in sorted(g, key=lambda s: s["source_hash"])
                ],
            }
            for i, g in enumerate(groups)
        },
    }


def freeze(root):
    refs = [json.loads(p.read_text()) for p in sorted((root / "labels/provisional").glob("*.json"))]
    hashes = {e["sha256"] for e in json.loads((root / "inventory.json").read_text())["entries"]}
    if {h for r in refs for h in r["document_hashes"]} != hashes:
        raise ValueError("Every original must have exactly one reference before splitting.")
    result = grouping(refs)
    path = root / "split.json"
    if path.exists():
        old = json.loads(path.read_text())
        if old.get("grouping_verified"):
            if old.get("relationships_hash") != result["relationships_hash"]:
                raise ValueError(
                    "Frozen relationships changed; archive the prior experiment before creating a new dataset version."
                )
            return old
    for ref in refs:
        ref["day_id"] = next(
            k
            for k, g in result["days"].items()
            if ref["document_hashes"][0] in g["document_hashes"]
        )
        ref.update(verified=False, reviewed_at=None, approval_hash=None, content_hash=None)
        write(root / "labels/provisional" / f"{ref['document_hashes'][0]}.json", ref)
    write(path, result)
    return result


def matrix(recipe, w, h):
    if "turn" in recipe:
        return [
            ([1, 0, 0, 0, 1, 0, 0, 0, 1], (w, h)),
            ([0, -1, h, 1, 0, 0, 0, 0, 1], (h, w)),
            ([-1, 0, w, 0, -1, h, 0, 0, 1], (w, h)),
            ([0, 1, 0, -1, 0, w, 0, 0, 1], (h, w)),
        ][recipe["turn"]]
    if recipe.get("mirror") == "horizontal":
        return [-1, 0, w, 0, 1, 0, 0, 0, 1], (w, h)
    if recipe.get("mirror") == "vertical":
        return [1, 0, 0, 0, -1, h, 0, 0, 1], (w, h)
    if "angle" in recipe:
        angle = math.radians(recipe["angle"])
        c, s = math.cos(angle), math.sin(angle)
        return [
            c,
            -s,
            (1 - c) * w / 2 + s * h / 2,
            s,
            c,
            (1 - c) * h / 2 - s * w / 2,
            0,
            0,
            1,
        ], (w, h)
    if "perspective" in recipe:
        p = recipe["perspective"]
        return [1, 0, 0, p * h / w, 1, 0, p / w, 0, 1], (w, h)
    scale = recipe.get("scale", 1)
    return [scale, 0, 0, 0, scale, 0, 0, 0, 1], (round(w * scale), round(h * scale))


def inverse(m):
    a, b, c, d, e, f, g, h, i = m
    det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    return [
        v / det
        for v in [
            e * i - f * h,
            c * h - b * i,
            b * f - c * e,
            f * g - d * i,
            a * i - c * g,
            c * d - a * f,
            d * h - e * g,
            b * g - a * h,
            a * e - b * d,
        ]
    ]


def transform(m, polygon):
    return [
        {
            "x": (m[0] * p["x"] + m[1] * p["y"] + m[2]) / (m[6] * p["x"] + m[7] * p["y"] + m[8]),
            "y": (m[3] * p["x"] + m[4] * p["y"] + m[5]) / (m[6] * p["x"] + m[7] * p["y"] + m[8]),
        }
        for p in polygon
    ]


def variant(image, ref, recipe):
    # Patient/header data outside the approved table are never present in exports.
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).polygon(
        [(p["x"], p["y"]) for p in ref["sources"][0]["table_polygon"]], fill=255
    )
    image = Image.composite(image, Image.new("RGB", image.size, "white"), mask)
    m, size = matrix(recipe, *image.size)
    inv = inverse(m)
    output = image.transform(
        size,
        Image.Transform.PERSPECTIVE,
        [v / inv[8] for v in inv[:8]],
        Image.Resampling.BICUBIC,
        fillcolor="white",
    )
    for key, enhancer in [
        ("brightness", ImageEnhance.Brightness),
        ("contrast", ImageEnhance.Contrast),
    ]:
        if key in recipe:
            output = enhancer(output).enhance(recipe[key])
    if "blur" in recipe:
        output = output.filter(ImageFilter.GaussianBlur(recipe["blur"]))
    if "shadow" in recipe:
        gradient = Image.linear_gradient("L").rotate(90).resize(size)
        if recipe["shadow"] < 0:
            gradient = ImageOps.mirror(gradient)
        gradient = gradient.point(lambda v: 110 + int(v * 145 / 255))
        output = Image.composite(output, Image.new("RGB", size, "black"), gradient)
    obstruction = None
    if "cut" in recipe:
        obstruction = (int(size[0] * recipe["cut"]), 0, size[0], size[1])
    if recipe.get("cover"):
        obstruction = (
            int(size[0] * 0.48),
            int(size[1] * 0.42),
            int(size[0] * 0.56),
            int(size[1] * 0.64),
        )
    if obstruction:
        ImageDraw.Draw(output).rectangle(obstruction, fill="white")
    return output, variant_labels(ref, recipe)[0], m


def variant_labels(ref, recipe):
    source = ref["sources"][0]
    m, size = matrix(recipe, source["width"], source["height"])
    obstruction = None
    if "cut" in recipe:
        obstruction = (int(size[0] * recipe["cut"]), 0, size[0], size[1])
    if recipe.get("cover"):
        obstruction = (
            int(size[0] * 0.48),
            int(size[1] * 0.42),
            int(size[0] * 0.56),
            int(size[1] * 0.64),
        )
    lines = []
    for line in ref["lines"]:
        p = transform(m, line["polygon"])
        xs, ys = [v["x"] for v in p], [v["y"] for v in p]
        cropped = min(xs) < 0 or min(ys) < 0 or max(xs) > size[0] or max(ys) > size[1]
        covered = (
            obstruction
            and max(xs) > obstruction[0]
            and min(xs) < obstruction[2]
            and max(ys) > obstruction[1]
            and min(ys) < obstruction[3]
        )
        state = (
            "cropped"
            if cropped or (covered and "cut" in recipe)
            else "illegible"
            if covered
            else line["state"]
        )
        lines.append(
            {
                **line,
                "polygon": p,
                "state": state,
                "text": line["text"] if state == "legible" else "",
            }
        )
    return lines, m, size


def bound_cache(cache, budget):
    files = sorted(
        (p for p in cache.glob("*.jpg") if p.is_file()),
        key=lambda p: (p.stat().st_mtime_ns, p.name),
    )
    size = sum(p.stat().st_size for p in files)
    for path in files:
        if size <= budget:
            break
        size -= path.stat().st_size
        path.unlink()
        path.with_suffix(".json").unlink(missing_ok=True)


def recipes(root):
    split = json.loads((root / "split.json").read_text())
    if split.get("schema_version") != 3 or not split.get("grouping_verified"):
        raise ValueError("Freeze confirmed development groups before augmentation.")
    manifest = {
        "schema_version": VERSION,
        "split_hash": digest(split),
        "recipes": [],
        "final_holdout": False,
    }
    for group_id, group in split["days"].items():
        for source in group["document_hashes"]:
            for name, recipe in RECIPES:
                manifest["recipes"].append(
                    {
                        "id": digest([VERSION, source, name, recipe]),
                        "source_hash": source,
                        "group": group_id,
                        "fold": group["fold"],
                        "name": name,
                        "recipe": recipe,
                        "recognition_eligible": "mirror" not in recipe,
                        "purpose": "orientation_only" if "mirror" in recipe else "robustness",
                    }
                )
    write(root / "variants/recipes.json", manifest)
    return manifest


def export(root, output, fold, cache_mb):
    manifest = recipes(root)
    inventory = {
        e["sha256"]: e for e in json.loads((root / "inventory.json").read_text())["entries"]
    }
    refs = {
        h: json.loads((root / "labels/provisional" / f"{h}.json").read_text()) for h in inventory
    }
    for ref in refs.values():
        approved(ref)
    checked_crops = reviewed_crops(root, refs.values())
    if grouping(list(refs.values())) != json.loads((root / "split.json").read_text()):
        raise ValueError("Frozen source relationships changed.")
    output.mkdir(parents=True, exist_ok=False)
    cache = root / "variants/cache"
    cache.mkdir(parents=True, exist_ok=True)
    records, detection, recognition, tables, orientation = [], [], [], [], []
    for entry in manifest["recipes"]:
        h = entry["source_hash"]
        ref = refs[h]
        source = ref["sources"][0]
        lines, m, size = variant_labels(ref, entry["recipe"])
        provenance = {
            **entry,
            "partition": "validation" if entry["fold"] == fold else "train",
            "reference_hash": reference_hash(ref),
            "original_hash": source["original_hash"],
            "original_to_variant": m,
            "variant_to_original": inverse(m),
            "size": size,
        }
        records.append(provenance)
        orientation.append(
            {
                **provenance,
                "quarter_turns": entry["recipe"].get("turn", 0),
                "mirror": entry["recipe"].get("mirror"),
            }
        )
        # Mirrored glyphs train orientation correction only. Recognition never
        # sees an unchanged normal label paired with mirrored text.
        if not entry["recognition_eligible"]:
            continue
        # Shared date headings link to several rows but appear once on the page.
        unique_lines = {}
        for line in lines:
            key = digest([normalized_numbers(line["polygon"]), line["state"], line["text"]])
            unique_lines.setdefault(key, line)
        detection.append(
            {
                **provenance,
                "labels": [
                    {
                        "points": [[p["x"], p["y"]] for p in line["polygon"]],
                        "transcription": line["text"] if line["state"] == "legible" else "###",
                        "line_id": line["id"],
                        "state": line["state"],
                    }
                    for line in unique_lines.values()
                ],
            }
        )
        # Incomplete detection labels would teach the model to ignore real text.
        if any(line["id"] not in checked_crops for line in unique_lines.values()):
            detection.pop()
        for line in unique_lines.values():
            if line["id"] in checked_crops and line["state"] == "legible" and line["text"]:
                recognition.append(
                    {
                        **provenance,
                        "line_id": line["id"],
                        "polygon": line["polygon"],
                        "text": line["text"],
                        "character_count": len(line["text"]),
                    }
                )
        rows = []
        for a in ref["appointments"]:
            fields = {}
            for f, assessment in a["fields"].items():
                field_lines = [
                    line
                    for line in lines
                    if line["appointment_id"] == a["id"] and line["field"] == f
                ]
                state = assessment["state"]
                if any(line["state"] != "legible" for line in field_lines):
                    state = next(
                        line["state"] for line in field_lines if line["state"] != "legible"
                    )
                fields[f] = {
                    "state": state,
                    "polygon": transform(m, assessment["polygon"]),
                    "frame": "variant",
                    "value": a.get(f) if state in {"legible", "not_printed"} else None,
                    "line_ids": [line["id"] for line in field_lines],
                }
            rows.append(
                {
                    "id": a["id"],
                    "row_polygon": transform(m, a["row_polygon"]),
                    "fields": fields,
                }
            )
        tables.append({**provenance, "rows": rows})
    for name, values in [
        ("detection", detection),
        ("recognition", recognition),
        ("table-assignment", tables),
        ("orientation", orientation),
    ]:
        (output / f"{name}.jsonl").write_text(
            "".join(json.dumps(v, ensure_ascii=False) + "\n" for v in values)
        )
    write(
        output / "manifest.json",
        {
            "schema_version": VERSION,
            "validation_fold": fold,
            "recipe_hash": digest(manifest),
            "reference_hashes": {h: reference_hash(r) for h, r in refs.items()},
            "records": records,
            "cache_bytes": cache_mb * 1024 * 1024,
            "training_started": False,
            "separately_reviewed_crops": len(checked_crops),
            "recognition_examples": len(recognition),
            "files": {
                name: file_hash(output / name)
                for name in [
                    "detection.jsonl",
                    "recognition.jsonl",
                    "table-assignment.jsonl",
                    "orientation.jsonl",
                ]
            },
            "validation_policy": "Report originals separately; derivatives are correlated robustness checks, never extra independent samples.",
        },
    )
    bound_cache(cache, cache_mb * 1024 * 1024)
    return len(records)


def materialize(root, identifier, cache_mb):
    manifest = json.loads((root / "variants/recipes.json").read_text())
    entry = next(r for r in manifest["recipes"] if r["id"] == identifier)
    ref = json.loads((root / "labels/provisional" / f"{entry['source_hash']}.json").read_text())
    approved(ref)
    split = json.loads((root / "split.json").read_text())
    if digest(split) != manifest["split_hash"] or not split.get("grouping_verified"):
        raise ValueError("Split changed; invalidate derived cache and exports.")
    references = [
        json.loads((root / "labels/provisional" / f"{h}.json").read_text())
        for g in split["days"].values()
        for h in g["document_hashes"]
    ]
    if grouping(references) != split:
        raise ValueError("Frozen source relationships changed.")
    source = next(
        e
        for e in json.loads((root / "inventory.json").read_text())["entries"]
        if e["sha256"] == entry["source_hash"]
    )
    path = root / "raw" / source["filename"]
    if file_hash(path) != entry["source_hash"]:
        raise ValueError("Original checksum mismatch.")
    with Image.open(path) as original:
        raster, lines, m = variant(original.convert("RGB"), ref, entry["recipe"])
    key = digest([identifier, reference_hash(ref)])
    cache = root / "variants/cache"
    cache.mkdir(parents=True, exist_ok=True)
    raster.save(cache / f"{key}.jpg", quality=entry["recipe"].get("quality", 92))
    write(
        cache / f"{key}.json",
        {
            **entry,
            "reference_hash": reference_hash(ref),
            "original_to_variant": m,
            "lines": lines,
        },
    )
    bound_cache(cache, cache_mb * 1024 * 1024)
    path = cache / f"{key}.jpg"
    if not path.exists():
        raise ValueError("One variant exceeds the configured cache budget.")
    return path


def homography(a, b):
    rows = []
    for source, target in zip(a, b):
        x, y = source["x"], source["y"]
        u, v = target["x"], target["y"]
        rows.extend(
            [
                [x, y, 1, 0, 0, 0, -u * x, -u * y, u],
                [0, 0, 0, x, y, 1, -v * x, -v * y, v],
            ]
        )
    for col in range(8):
        pivot = max(range(col, 8), key=lambda row: abs(rows[row][col]))
        rows[col], rows[pivot] = rows[pivot], rows[col]
        divisor = rows[col][col]
        if abs(divisor) < 1e-10:
            raise ValueError("Degenerate text polygon.")
        rows[col] = [v / divisor for v in rows[col]]
        for i in range(8):
            if i != col:
                factor = rows[i][col]
                rows[i] = [v - factor * p for v, p in zip(rows[i], rows[col])]
    return [row[8] for row in rows] + [1]


def line_crop(image, polygon):
    if len(polygon) != 4:
        raise ValueError("Recognition crops require four confirmed polygon corners.")

    def distance(a, b):
        return math.hypot(a["x"] - b["x"], a["y"] - b["y"])

    w = math.ceil(max(distance(polygon[0], polygon[1]), distance(polygon[3], polygon[2])))
    h = math.ceil(max(distance(polygon[0], polygon[3]), distance(polygon[1], polygon[2])))
    if w < 2 or h < 2 or w * h > 50_000_000:
        raise ValueError("Invalid crop dimensions.")
    to = [
        {"x": 0, "y": 0},
        {"x": w - 1, "y": 0},
        {"x": w - 1, "y": h - 1},
        {"x": 0, "y": h - 1},
    ]
    crop_to_variant = homography(to, polygon)
    crop = image.transform(
        (w, h),
        Image.Transform.PERSPECTIVE,
        [v / crop_to_variant[8] for v in crop_to_variant[:8]],
        Image.Resampling.BICUBIC,
        fillcolor="white",
    )
    return crop, crop_to_variant


def materialize_line(root, identifier, line_id, cache_mb):
    page = materialize(root, identifier, cache_mb)
    metadata = json.loads(page.with_suffix(".json").read_text())
    if not metadata["recognition_eligible"]:
        raise ValueError("Mirrored samples are orientation-only.")
    line = next(line for line in metadata["lines"] if line["id"] == line_id)
    references = [
        json.loads(path.read_text()) for path in (root / "labels/provisional").glob("*.json")
    ]
    if line_id not in reviewed_crops(root, references):
        raise ValueError("Review the full text crop separately before recognition training.")
    if line["state"] != "legible" or not line["text"]:
        raise ValueError("Unreadable and cropped text cannot receive a full recognition label.")
    with Image.open(page) as image:
        crop, to_variant = line_crop(image, line["polygon"])
    key = digest([VERSION, identifier, metadata["reference_hash"], line_id, "recognition"])
    target = page.parent / f"{key}.jpg"
    crop.save(target, quality=95)
    write(
        target.with_suffix(".json"),
        {
            **metadata,
            "lines": [line],
            "text": line["text"],
            "crop_to_variant": to_variant,
            "purpose": "text_line_recognition",
        },
    )
    bound_cache(page.parent, cache_mb * 1024 * 1024)
    if not target.exists():
        raise ValueError("Crop exceeds cache budget.")
    return target


def readiness(root):
    inventory = json.loads((root / "inventory.json").read_text())
    originals = {entry["sha256"] for entry in inventory["entries"]}
    approved_count = 0
    kinds = {"rehabilitation_plan": 0, "non_plan": 0, "unusable": 0}
    for source_hash in originals:
        path = root / "labels/provisional" / f"{source_hash}.json"
        if not path.exists():
            continue
        reference = json.loads(path.read_text())
        kind = reference.get("input_class", "rehabilitation_plan")
        if kind in kinds:
            kinds[kind] += 1
        try:
            approved(reference)
            approved_count += 1
        except ValueError:
            pass
    return {
        "original_photos": len(originals),
        "approved_references": approved_count,
        "draft_input_classes": kinds,
        "target_real_plan_photos": 40,
        "target_negative_or_unusable": 10,
        "missing_plan_photos": max(0, 40 - kinds["rehabilitation_plan"]),
        "missing_negative_or_unusable": max(0, 10 - kinds["non_plan"] - kinds["unusable"]),
        "independent_final_acceptance": False,
        "accuracy_changes_enabled": False,
    }


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--root", type=Path, default=Path("data/private"))
    sub = p.add_subparsers(dest="command", required=True)
    sub.add_parser("freeze")
    sub.add_parser("recipes")
    sub.add_parser("readiness")
    e = sub.add_parser("export")
    e.add_argument("output", type=Path)
    e.add_argument("--fold", type=int, choices=range(4), required=True)
    e.add_argument("--cache-mb", type=int, default=256)
    m = sub.add_parser("materialize")
    m.add_argument("id")
    m.add_argument("--cache-mb", type=int, default=256)
    line = sub.add_parser("materialize-line")
    line.add_argument("id")
    line.add_argument("line_id")
    line.add_argument("--cache-mb", type=int, default=256)
    a = p.parse_args()
    # All retained CLI writers share the Rust reference library's process lock.
    with sqlite3.connect(a.root / ".reference-lock.sqlite3", timeout=5) as lock:
        lock.execute("BEGIN IMMEDIATE")
        execute(a)


def execute(a):
    if a.command == "readiness":
        print(json.dumps(readiness(a.root), indent=2))
    elif a.command == "freeze":
        print(json.dumps({"groups": len(freeze(a.root)["days"]), "holdout": False}))
    elif a.command == "recipes":
        print(len(recipes(a.root)["recipes"]))
    elif a.command == "export":
        print(export(a.root, a.output, a.fold, a.cache_mb))
    elif a.command == "materialize-line":
        print(materialize_line(a.root, a.id, a.line_id, a.cache_mb))
    else:
        print(materialize(a.root, a.id, a.cache_mb))


if __name__ == "__main__":
    main()
