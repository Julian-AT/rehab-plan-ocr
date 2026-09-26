"""Portable dataset and validation rules for auditable OCR adaptation."""

import hashlib
import json
import math
import os

from PIL import Image

CRITICAL = {"date", "start_time", "end_time", "duration_minutes", "title", "location", "therapist"}


def field_name(value):
    value = {"start": "start_time", "end": "end_time"}.get(value, value)
    if value not in CRITICAL | {"notes"}:
        raise ValueError("Unknown OCR field; critical evidence cannot be silently excluded")
    return value


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def digest(value):
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, ensure_ascii=False).encode()
    ).hexdigest()


def write(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w") as stream:
        stream.write(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n")
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)


def validate_dataset(path, dictionary):
    dataset = json.loads(path.read_text())
    if dataset.get("schema_version") != 1 or dataset.get("kind") not in {
        "invented-smoke-text",
        "approved-reference-crops",
        "pixel-verified-synthetic-crops",
    }:
        raise ValueError("Unknown dataset contract")
    if dataset.get("final_holdout") is not False:
        raise ValueError("Final holdout cannot be used for training or checkpoint selection")
    if dataset["kind"] == "pixel-verified-synthetic-crops":
        from synthetic_data import verify

        verify(dataset)
    seen, assignments, rows = set(), {}, dataset["samples"]
    allowed = set(dictionary) | {" "}
    for row in rows:
        if field_name(row["field"]) != row["field"]:
            raise ValueError("Prepare canonical field names before training")
        if row["id"] in seen:
            raise ValueError("Duplicate sample identity")
        seen.add(row["id"])
        if row["partition"] not in {"train", "validation"}:
            raise ValueError("Only training and development validation are accepted")
        if row.get("state") != "legible" or not row["text"]:
            raise ValueError("Incomplete evidence cannot be a full-text training target")
        if any(c not in allowed for c in row["text"]):
            raise ValueError("Dictionary would discard target characters; nothing truncated")
        if not row.get("group") or not row.get("source_sha256"):
            raise ValueError("Source identity and grouping are required before training")
        for namespace, value in [
            ("group", row["group"]),
            ("source", row["source_sha256"]),
            ("image", row["image_sha256"]),
        ]:
            key = (namespace, value)
            if key in assignments and assignments[key] != row["partition"]:
                raise ValueError("Related data crosses training and validation partitions")
            assignments[key] = row["partition"]
        image = (path.parent / row["image"]).resolve(strict=True)
        if not image.is_relative_to(path.parent.resolve()) or sha(image) != row["image_sha256"]:
            raise ValueError("Training pixels changed or escaped the prepared dataset")
        with Image.open(image) as decoded:
            decoded.load()
            if min(decoded.size) < 2:
                raise ValueError("Unusable image dimensions")
    if {r["partition"] for r in rows} != {"train", "validation"}:
        raise ValueError("Nonempty training and grouped validation sets are required")
    if dataset["kind"] == "approved-reference-crops":
        receipt = path.parent / "references/manifest.json"
        if sha(receipt) != dataset["reference_export_sha256"]:
            raise ValueError("Reference export receipt changed")
        if any(
            not row.get("reference_hash")
            or not row.get("crop_review_hash")
            or not row.get("privacy_review_sha256")
            for row in rows
        ):
            raise ValueError(
                "Human field, separate crop and privacy review provenance are required"
            )
    return dataset


def selection(metrics):
    # Critical errors cannot be hidden by improvements on less consequential text.
    result = [metrics["critical_errors"], metrics["group_mean_error"], metrics["character_errors"]]
    if any(not math.isfinite(value) or value < 0 for value in result):
        raise ValueError("Validation must produce finite, nonnegative error measurements")
    return result


def advance(state, metrics, epoch, patience):
    score = selection(metrics)
    improved = state.get("best_score") is None or score < state["best_score"]
    result = dict(state, epoch=epoch, stale_epochs=0 if improved else state["stale_epochs"] + 1)
    if improved:
        result.update(best_score=score, best_epoch=epoch)
    result["stopped"] = result["stale_epochs"] >= patience
    return result
