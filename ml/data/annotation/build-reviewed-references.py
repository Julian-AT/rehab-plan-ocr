# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow==12.1.0"]
# ///
"""Turn independent visual transcriptions into unapproved, original-linked drafts.

Text comes only from the supplied transcription. OCR may suggest polygon locations
and error categories, never replacement truth. Source and polygon review is pending.
"""

import argparse
import hashlib
import json
import shutil
import uuid
from datetime import date as calendar_date
from difflib import SequenceMatcher
from pathlib import Path

from PIL import Image


def rect(x, y, r, b):
    return [
        {"x": float(x), "y": float(y)},
        {"x": float(r), "y": float(y)},
        {"x": float(r), "y": float(b)},
        {"x": float(x), "y": float(b)},
    ]


def clip(subject, boundary):
    """Convex clipping keeps all label polygons inside the declared table."""
    for i, a in enumerate(boundary):
        b = boundary[(i + 1) % len(boundary)]

        def cross(p, a=a, b=b):
            return (b["x"] - a["x"]) * (p["y"] - a["y"]) - (b["y"] - a["y"]) * (p["x"] - a["x"])

        result = []
        if not subject:
            break
        previous = subject[-1]
        for point in subject:
            c, d = cross(previous), cross(point)
            if (c >= 0) != (d >= 0):
                t = c / (c - d)
                result.append(
                    {
                        "x": previous["x"] + t * (point["x"] - previous["x"]),
                        "y": previous["y"] + t * (point["y"] - previous["y"]),
                    }
                )
            if d >= 0:
                result.append(point)
            previous = point
        subject = result
    return subject


def build(transcriptions, root, baseline):
    specs = json.loads(transcriptions.read_text())
    inventory = json.loads((root / "inventory.json").read_text())
    runs = [json.loads(p.read_text()) for p in sorted(baseline.glob("document-*/run.json"))]
    reports = []
    for entry in inventory["entries"]:
        spec = specs[Path(entry["filename"]).stem]
        source_hash = entry["sha256"]
        image = root / "raw" / entry["filename"]
        with image.open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != source_hash:
                raise ValueError("Original changed.")
        with Image.open(image) as original:
            w, h = original.size
        table_left, t, r, b = spec["table"]
        table = (
            [{"x": float(x * w), "y": float(y * h)} for x, y in spec["table_quad"]]
            if "table_quad" in spec
            else rect(table_left * w, t * h, r * w, b * h)
        )
        run = next(run for run in runs if run["document"]["source_hash"] == source_hash)
        old_path = root / "labels/provisional" / f"{source_hash}.json"
        old = json.loads(old_path.read_text())
        if old.get("schema_version") == 2:
            raise ValueError("Existing version-2 review preserved; use a new destination.")
        observations = []
        for o in run["observations"]:
            pts = [
                p
                for region in run["regions"]
                if region["id"] in o["region_ids"]
                for p in region["polygon"]
            ]
            if pts:
                observations.append(
                    (
                        o,
                        pts,
                        min(p["x"] for p in pts),
                        sum(p["y"] for p in pts) / len(pts),
                    )
                )
        appointments = []
        lines = []
        changes = []
        time_x, title_x, room_x, therapist_x = spec["columns"]
        ranges = {
            "start": (time_x, time_x + (title_x - time_x) * 0.47),
            "end": (time_x + (title_x - time_x) * 0.52, title_x - 0.025),
            "title": (title_x, room_x - 0.004),
            "location": (room_x, therapist_x - 0.004),
            "therapist": (therapist_x, r),
            "notes": (title_x, r),
        }
        for index, row in enumerate(spec["rows"]):
            date, top, bottom, start, end, title, location, therapist, notes = row
            top, bottom = float(top), float(bottom)
            identifier = str(uuid.uuid5(uuid.NAMESPACE_OID, f"{source_hash}:visual:{index}"))
            a = {
                "id": identifier,
                "section_id": f"visual-{date}",
                "metadata": {
                    key: ""
                    for key in [
                        "clinic",
                        "department",
                        "address",
                        "contact",
                        "treatment_code",
                        "preparation",
                        "document_reference",
                        "appointment_notes",
                    ]
                },
                "origins": {},
                "suggestions": [],
                "approval": None,
                "calendar_event_id": None,
                "ics_event_id": None,
                "calendar_saved_hash": None,
                "ics_exported_hash": None,
                "date": date,
                "start": start,
                "end": end or None,
                "end_date": None,
                "duration_minutes": None,
                "title": title.replace("|", " "),
                "location": location.replace("|", " "),
                "therapist": therapist.replace("|", " "),
                "notes": notes.replace("|", "\n"),
                "included": True,
                "provenance": {},
                "issues": [],
                "fields": {},
                "row_polygon": [],
            }
            all_polygons = []
            for field, printed in [
                ("date", date),
                ("start", start),
                ("end", end),
                ("title", title),
                ("location", location),
                ("therapist", therapist),
                ("notes", notes),
            ]:
                state = spec.get("states", {}).get(
                    f"{index}:{field}", "legible" if printed else "not_printed"
                )
                x1, x2 = ranges.get(field, (table_left, min(r, table_left + 0.30)))
                # A wholly off-frame cell stays linked to the visible table edge.
                x1 = min(x1, r - 0.002)
                x2 = max(x1 + 0.001, x2)
                y1 = (
                    spec["days"][date]
                    if field == "date"
                    else top + spec.get("slant", 0) * (x1 - time_x)
                )
                y2 = y1 + 0.02 if field == "date" else bottom + spec.get("slant", 0) * (x1 - time_x)
                polygon = clip(rect(x1 * w, y1 * h, min(x2, r) * w, min(y2, b) * h), table)
                if len(polygon) < 4:
                    polygon = clip(
                        rect(
                            x1 * w,
                            (top + 0.003) * h,
                            min(x2, r) * w,
                            min(bottom, b) * h,
                        ),
                        table,
                    )
                assessment = {
                    "state": state,
                    "polygon": polygon,
                    "frame": "original",
                    "reasons": [],
                    "confirmed_value": None,
                    "confirmed_at": None,
                }
                a["fields"][field] = assessment
                if field != "date":
                    all_polygons.extend(polygon)
                if not printed:
                    continue
                texts = printed.split("|")
                if field == "date":
                    day = calendar_date.fromisoformat(date)
                    texts = [
                        f"{['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'][day.weekday()]}, der {day:%d.%m.%Y}"
                    ]
                for k, text in enumerate(texts):
                    height = min(0.017, (y2 - y1) / max(len(texts), 1))
                    ly = y1 + k * height
                    if field == "notes":
                        ly = max(y1, y2 - height * len(texts)) + k * height
                    expected_y = ly * h
                    possible = [
                        item
                        for item in observations
                        if abs(item[3] - expected_y) < max(80, (bottom - top) * h)
                        and item[2] >= x1 * w - 30
                        and item[2] < x2 * w + 30
                    ]
                    candidate = max(
                        possible,
                        key=lambda v: (
                            SequenceMatcher(None, text, v[0]["text"]).ratio()
                            - abs(v[3] - expected_y) / h
                        ),
                        default=None,
                    )
                    similarity = (
                        SequenceMatcher(None, text, candidate[0]["text"]).ratio()
                        if candidate
                        else 0
                    )
                    poly = clip(candidate[1], polygon) if candidate and similarity > 0.60 else []
                    if len(poly) < 4:
                        poly = clip(rect(x1 * w, ly * h, x2 * w, (ly + height) * h), table)
                    if len(poly) < 4:
                        poly = polygon
                    causes = []
                    if state == "cropped":
                        causes.append("image_quality")
                    elif similarity < 0.60:
                        causes.append("text_detection")
                    elif similarity < 0.98:
                        causes.append("character_recognition")
                    if field in {"location", "therapist"}:
                        previous = [
                            v
                            for v in run["appointments"]
                            if v.get("start") == start and v.get("date") == date
                        ]
                        if len(previous) == 1 and previous[0].get(field, "") != a[field]:
                            causes.append(
                                "column_assignment"
                                if any(
                                    z in previous[0].get("location", "")
                                    for z in ["BSc", "Fr.", "Hr."]
                                )
                                else "row_assignment"
                            )
                    lines.append(
                        {
                            "id": f"{identifier}-{field}-{k}",
                            "source_hash": source_hash,
                            "appointment_id": identifier,
                            "field": field,
                            "text": text,
                            "polygon": poly,
                            "state": state,
                            "error_causes": causes,
                        }
                    )
                    if causes:
                        changes.append(
                            {
                                "appointment_id": identifier,
                                "field": field,
                                "causes": causes,
                                "assessment": "proposed_cause_pending_user_review",
                            }
                        )
            if all_polygons:
                a["row_polygon"] = clip(
                    rect(
                        min(p["x"] for p in all_polygons),
                        top * h,
                        max(p["x"] for p in all_polygons),
                        min(b, bottom + abs(spec.get("slant", 0))) * h,
                    ),
                    table,
                )
            appointments.append(a)
        ref = {
            "schema_version": 2,
            "day_id": old["day_id"],
            "document_hashes": [source_hash],
            "verified": False,
            "reviewed_at": None,
            "split": "development",
            "appointments": appointments,
            "uncertainty_notes": [
                "Visuell transkribierter Entwurf: Feldtexte, Textpolygone und vollständige Erfassung gemeinsam bestätigen."
            ],
            "sources": [
                {
                    "source_hash": source_hash,
                    "original_hash": entry["original_sha256"],
                    "logical_page": spec["logical_page"],
                    "capture_series": Path(entry["filename"]).stem,
                    "treatment_days": sorted(spec["days"]),
                    "width": w,
                    "height": h,
                    "table_polygon": table,
                    "relationships_confirmed": False,
                }
            ],
            "lines": lines,
            "coverage_confirmed": False,
            "content_hash": None,
            "approval_hash": None,
        }
        archive = root / "labels/ocr-seed-v1"
        archive.mkdir(exist_ok=True)
        shutil.copy2(old_path, archive / old_path.name)
        old_path.write_text(json.dumps(ref, ensure_ascii=False, indent=2) + "\n")
        reports.append(
            {
                "source_hash": source_hash,
                "original_hash": entry["original_sha256"],
                "filename": entry["filename"],
                "visually_inspected": True,
                "transcribed_appointments": len(appointments),
                "transcribed_lines": len(lines),
                "audit_note": spec["audit_note"],
                "errors": changes,
                "user_approved": False,
                "calendar_comparison": "No live-calendar truth used; no calendar values modified.",
            }
        )
    output = root / "visual-review.json"
    output.write_text(
        json.dumps(
            {
                "schema_version": 2,
                "images": reports,
                "source_transcription_hash": hashlib.sha256(
                    transcriptions.read_bytes()
                ).hexdigest(),
                "approved": False,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n"
    )
    return {
        "images": len(reports),
        "appointments": sum(r["transcribed_appointments"] for r in reports),
        "approved": 0,
    }


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("transcriptions", type=Path)
    p.add_argument("--root", type=Path, default=Path(".local/datasets/private"))
    p.add_argument("--baseline", type=Path, required=True)
    a = p.parse_args()
    print(json.dumps(build(a.transcriptions, a.root, a.baseline)))
