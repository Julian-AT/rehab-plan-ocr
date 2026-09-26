"""Explicit, source-bound privacy and purpose review for real training exports.

This module verifies operator attestations; it never grants consent or human
approval. The authoritative intake receipt stays private and must be updated
when its purposes, retention or consent status change.
"""

import copy
import hashlib
import json
import math
import re
from datetime import date, datetime, timezone
from pathlib import Path

from PIL import ImageDraw

VERSION = 1
REASONS = {"patient_identity", "unrelated_identity"}


def file_hash(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def digest(value):
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()
    ).hexdigest()


def approval_hash(review):
    return digest({key: value for key, value in review.items() if key != "approval_hash"})


def opaque(value):
    return isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,79}", value)


def reviewed_at(value):
    parsed = datetime.fromisoformat(value)
    if parsed.tzinfo is None or parsed > datetime.now(timezone.utc):
        raise ValueError("Privacy/consent review requires a past timestamp with timezone")


def hash_value(value):
    return isinstance(value, str) and re.fullmatch("[a-f0-9]{64}", value)


def rectangles(review, source):
    result = []
    for area in review["redactions"]:
        rect = area["rect"]
        if (
            area.get("reason") not in REASONS
            or not isinstance(rect, list)
            or len(rect) != 4
            or any(
                isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v)
                for v in rect
            )
            or not 0 <= rect[0] < rect[2] <= source["width"]
            or not 0 <= rect[1] < rect[3] <= source["height"]
        ):
            raise ValueError("Privacy masks require finite original-pixel rectangles and a reason")
        # Cover boundary pixels and a two-pixel safety margin before any resampling.
        result.append(
            [
                max(0, math.floor(rect[0]) - 2),
                max(0, math.floor(rect[1]) - 2),
                min(source["width"], math.ceil(rect[2]) + 2),
                min(source["height"], math.ceil(rect[3]) + 2),
            ]
        )
    return result


def authorization(root, review, source, today):
    authorization = review["authorization"]
    path = root / authorization["intake_manifest"]
    if path.is_symlink() or not path.is_file() or file_hash(path) != authorization["intake_sha256"]:
        raise ValueError("Reviewed intake receipt changed or is unavailable")
    intake = json.loads(path.read_text())
    if (
        intake.get("schema_version") != 1
        or intake.get("status") != "awaiting_privacy_and_reference_review"
    ):
        raise ValueError("A complete, verified intake receipt is required for training")
    entries = [entry for entry in intake["entries"] if entry["id"] == authorization["entry_id"]]
    if len(entries) != 1:
        raise ValueError("Privacy review must select one explicit intake entry")
    entry = entries[0]
    if (
        entry.get("kind") != "schedule"
        or entry.get("copy_verified") is not True
        or entry.get("source_sha256") != source["original_hash"]
        or "ocr_training" not in entry.get("purposes", [])
        or not entry.get("related_ids")
        or len(set(entry["related_ids"])) != len(entry["related_ids"])
        or any(not opaque(value) for value in entry["related_ids"])
    ):
        raise ValueError(
            "Original, source relationships or OCR-training purpose differ from intake"
        )
    consents = [item for item in intake["consents"] if item["id"] == entry["consent_id"]]
    if len(consents) != 1:
        raise ValueError("Intake entry must retain its consent receipt")
    consent = consents[0]
    if (
        consent.get("status") != "active"
        or "ocr_training" not in consent.get("purposes", [])
        or date.fromisoformat(consent["retain_until"]) <= today
        or not opaque(consent.get("reviewer_id"))
        or not hash_value(consent.get("evidence_sha256"))
    ):
        raise ValueError("Active, reviewed consent for OCR training is required")
    reviewed_at(consent["reviewed_at"])
    return entry, consent


def checked_review(root, ref, review, reference_hash, today):
    if (
        review.get("reference_hash") != reference_hash(ref)
        or review.get("table_privacy_reviewed") is not True
        or not opaque(review.get("reviewer_id"))
        or not review.get("reviewed_at")
        or not isinstance(review.get("redactions"), list)
        or review.get("approval_hash") != approval_hash(review)
    ):
        raise ValueError("Privacy review is unapproved or changed after approval")
    reviewed_at(review["reviewed_at"])
    rectangles(review, ref["sources"][0])
    return authorization(root, review, ref["sources"][0], today)


def validate(root, references, reference_hash, today=None):
    """Return private runtime reviews and content-free export provenance separately."""
    references = list(references)
    today = today or date.today()
    path = root / "privacy-review.json"
    if not path.is_file() or path.is_symlink():
        raise ValueError("Separate privacy and OCR-purpose review is required before export")
    value = json.loads(path.read_text())
    expected = {ref["sources"][0]["source_hash"] for ref in references}
    if value.get("schema_version") != VERSION or not expected <= set(value.get("sources", {})):
        raise ValueError("Every original needs a separate privacy review")
    split = json.loads((root / "split.json").read_text())
    groups = {
        source: group for group, item in split["days"].items() for source in item["document_hashes"]
    }
    relationships = {}
    reviews, provenance = {}, {}
    for ref in references:
        source = ref["sources"][0]
        source_hash = source["source_hash"]
        review = value["sources"][source_hash]
        entry, consent = checked_review(root, ref, review, reference_hash, today)
        for relationship in entry["related_ids"]:
            group = groups[source_hash]
            if relationships.setdefault(relationship, group) != group:
                raise ValueError("Related intake originals must remain in one frozen source group")
        reviews[source_hash] = review
        provenance[source_hash] = {
            "review_sha256": review["approval_hash"],
            "intake_sha256": review["authorization"]["intake_sha256"],
            "consent_evidence_sha256": consent["evidence_sha256"],
            "relationships_sha256": digest(sorted(entry["related_ids"])),
        }
    return reviews, {
        "schema_version": VERSION,
        "review_file_sha256": file_hash(path),
        "validator_sha256": file_hash(Path(__file__)),
        "sources": provenance,
    }


def draft(references, reference_hash):
    return {
        "schema_version": VERSION,
        "sources": {
            ref["sources"][0]["source_hash"]: {
                "reference_hash": reference_hash(ref),
                "table_privacy_reviewed": False,
                "reviewer_id": None,
                "reviewed_at": None,
                "redactions": [],
                "authorization": {"intake_manifest": "", "intake_sha256": "", "entry_id": ""},
                "approval_hash": None,
            }
            for ref in references
        },
    }


def confirm(root, ref, reviewer, reference_hash):
    """Only the explicit human-facing confirmation command calls this writer."""
    path = root / "privacy-review.json"
    value = json.loads(path.read_text())
    if value.get("schema_version") != VERSION:
        raise ValueError("Unsupported privacy-review schema")
    source = ref["sources"][0]["source_hash"]
    review = value["sources"][source]
    # The operator must explicitly edit the attestation after checking the
    # actual original, complete table, masks and allowed use. A CLI invocation
    # alone cannot silently turn the generated unreviewed draft into approval.
    if review.get("table_privacy_reviewed") is not True:
        raise ValueError("Confirm the table privacy review in the draft first")
    review["reviewer_id"] = reviewer
    review["reviewed_at"] = datetime.now(timezone.utc).isoformat()
    review["approval_hash"] = approval_hash(review)
    checked_review(root, ref, review, reference_hash, date.today())
    return value


def sanitized(ref, review):
    """Never modify original references or carry redacted field truth into labels."""
    result = copy.deepcopy(ref)
    # Free-form review diagnostics remain with the private reference. A training
    # sidecar needs only these source links, geometry, state and transcription.
    result["lines"] = [
        {
            key: line[key]
            for key in ["id", "source_hash", "appointment_id", "field", "text", "polygon", "state"]
        }
        for line in result["lines"]
    ]
    masks = rectangles(review, result["sources"][0])

    def touches(polygon):
        if not polygon:
            return False
        xs, ys = [p["x"] for p in polygon], [p["y"] for p in polygon]
        return any(
            max(xs) >= x0 and min(xs) <= x1 and max(ys) >= y0 and min(ys) <= y1
            for x0, y0, x1, y1 in masks
        )

    removed = {
        (line["appointment_id"], line["field"])
        for line in result["lines"]
        if touches(line["polygon"])
    }
    for appointment in result["appointments"]:
        for name, field in appointment["fields"].items():
            if touches(field["polygon"]):
                removed.add((appointment["id"], name))
        for name in appointment["fields"]:
            if (appointment["id"], name) in removed:
                appointment[name] = None
                appointment["fields"][name]["state"] = "illegible"
    for line in result["lines"]:
        if (line["appointment_id"], line["field"]) in removed:
            line["text"] = ""
            line["state"] = "illegible"
    return result


def mask_image(image, ref, review):
    image = image.copy()
    draw = ImageDraw.Draw(image)
    for x0, y0, x1, y1 in rectangles(review, ref["sources"][0]):
        draw.rectangle((x0, y0, x1, y1), fill="white")
    return image
