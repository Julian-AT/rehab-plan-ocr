# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow==12.1.1"]
# ///
"""Generate reproducible invented tables, negative inputs and pixel-checked labels.

Names, rooms and treatments are sampled independently. Synthetics are training
or robustness data only, never evidence of accuracy on original clinic photos.
"""

import argparse
import hashlib
import json
import platform
import random
from datetime import date, timedelta
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont
from PIL import __version__ as PILLOW_VERSION

VERSION = 2
SEED = 814_620
TITLES = [
    "Frühstück",
    "Mittagessen",
    "Abendessen",
    "Bewegungsgruppe",
    "Einzeltherapie",
    "Kreativwerkstatt",
    "Entspannung",
    "Koordination und Gleichgewicht",
    "Training Alltag",
    "Gespräch",
]
NAMES = [
    "Fr. A. Avenor, BSc",
    "Hr. M. Belvara, MSc",
    "Fr. T. Cendri",
    "Hr. Dr. R. Dalmorin",
    "Fr. L. Elandora-Windorin, BSc",
    "Hr. Mag. B. Fentari, BA",
]
ROOMS = [
    "Raum 101",
    "Raum 107",
    "Raum 701",
    "Raum 117",
    "1. Stock Wartezone Q",
    "EG Therapie 2",
    "OG Therapie 8",
    "Speisesaal",
]


def rect(x, y, w, h):
    return [
        {"x": x, "y": y},
        {"x": x + w, "y": y},
        {"x": x + w, "y": y + h},
        {"x": x, "y": y + h},
    ]


def wrap(value, font, width):
    """Wrap whole words where possible, including unbroken words wider than a cell."""

    def length(text):
        box = font.getbbox(text)
        return max(font.getlength(text), box[2] - box[0])

    lines = []
    for word in value.split():
        if lines and length(lines[-1] + " " + word) <= width:
            lines[-1] += " " + word
            continue
        part = ""
        for char in word:
            if part and length(part + char) > width:
                lines.append(part)
                part = ""
            if length(char) > width:
                raise ValueError("Cell is narrower than a glyph; no label may be truncated")
            part += char
        if part:
            lines.append(part)
    return lines


def bounds(polygon):
    return (
        min(p["x"] for p in polygon),
        min(p["y"] for p in polygon),
        max(p["x"] for p in polygon),
        max(p["y"] for p in polygon),
    )


def render(index, font_path):
    rng = random.Random(SEED + index)
    width = 1600
    font_size = [22, 24, 27][index % 3]
    font = ImageFont.truetype(str(font_path), font_size)
    spacing = sum(font.getmetrics()) + 7
    lines, rows, days, backgrounds = [], [], [], []

    def text(value, x, y, limit, owner, field, background="white"):
        ids = []
        for n, line in enumerate(wrap(value, font, limit)):
            box = font.getbbox(line)
            # Glyph bearings may extend left of the pen (e.g. Arial's A).
            # Position the ink inside the cell rather than widening its label.
            origin = (x - box[0], y + n * spacing - min(0, box[1]))
            box = (x, origin[1] + box[1], origin[0] + box[2], origin[1] + box[3])
            identifier = f"{owner}-{field}-{n}"
            ids.append(identifier)
            lines.append(
                {
                    "id": identifier,
                    "appointment_id": owner,
                    "field": field,
                    "text": line,
                    "state": "legible",
                    "origin": list(origin),
                    "background": background,
                    "polygon": rect(box[0], box[1], box[2] - box[0], box[3] - box[1]),
                }
            )
        return ids

    kind = "non_plan" if index % 20 == 18 else "unusable" if index % 20 == 19 else "schedule"
    order = (["title", "location", "therapist"], ["therapist", "title", "location"])[index % 2]
    columns = [("start", 60, 98), ("end", 190, 110)]
    x = 350
    for field in order:
        cell_width = {"title": 500, "location": 260, "therapist": 350}[field]
        columns.append((field, x, cell_width))
        x += cell_width + 35
    labels = {
        "start": "Beginn",
        "end": "Ende",
        "title": "Therapie",
        "location": "Raum",
        "therapist": "Therapeut",
    }
    y = 100
    if kind == "non_plan":
        text("ERFUNDENE EINKAUFSLISTE", 60, 40, 1400, "document", "header")
        for item in ["Brot", "Äpfel", "Notizbuch", "Batterien"]:
            text(item, 60, y, 1400, f"item-{y}", "other")
            y += 70
    elif kind == "schedule":
        text("ERFUNDENER TESTPLAN · keine Patientendaten", 60, 40, 1400, "document", "header")
        for day_number in range(2 if index % 3 == 0 else 1):
            day = (date(2030, 1, 1) + timedelta(days=index * 3 + day_number)).isoformat()
            day_id = f"day-{index}-{day_number}"
            date_lines = text(day, 60, y, 400, day_id, "date")
            date_polygon = lines[-1]["polygon"]
            y += spacing + 15
            for field, x, limit in columns:
                text(labels[field], x, y, limit, day_id, "column-" + field)
            y += spacing + 20
            members = []
            for n in range(rng.randint(5, 7) if index % 3 == 0 else rng.randint(8, 13)):
                rid = f"synthetic-{index:03}-{day_number}-{n:02}"
                start = rng.choice([420, 450, 480]) + n * rng.choice([20, 30, 40])
                end = start + rng.choice([15, 20, 30, 45])
                row = {
                    "id": rid,
                    "date": day,
                    "start": f"{start // 60:02}:{start % 60:02}",
                    "end": f"{end // 60:02}:{end % 60:02}",
                    "title": rng.choice(TITLES),
                    "location": rng.choice(ROOMS),
                    "therapist": rng.choice(NAMES),
                    "notes": rng.choice(
                        ["", "", "bitte feste Schuhe mitbringen", "Handtuch mitnehmen"]
                    ),
                }
                if rng.random() < 0.15:
                    row["location"] = ""
                if rng.random() < 0.2:
                    row["therapist"] = ""
                if n == 2:
                    row["therapist"] = "Fr. L. Elandora-Windorin, BSc"
                if n == 3 and index % 4 == 0:
                    row["therapist"] += " / Hr. M. Belvara, MSc"
                if n == 4 and index % 5 == 0:
                    row.update(
                        {
                            key: rows[-1][key]
                            for key in ["start", "end", "title", "location", "therapist"]
                        }
                    )
                if n == 5 and index % 3 == 0:
                    row["start"], row["end"] = rows[-1]["start"], rows[-1]["end"]
                lengths = {
                    field: max(1, len(wrap(row[field], font, limit))) * spacing
                    for field, _, limit in columns
                }
                title_x, title_width = next(
                    (x, limit) for field, x, limit in columns if field == "title"
                )
                notes_height = max(1, len(wrap(row["notes"], font, title_width))) * spacing
                row_height = max(*lengths.values(), lengths["title"] + notes_height + 10) + 24
                background = ["#eeeeee", "#edf4ed", "#f5efe4"][index % 3] if n % 2 == 0 else "white"
                backgrounds.append(((40, y - 8, 1560, y + row_height - 8), background))
                fields = {}
                for field, x, limit in [*columns, ("notes", title_x, title_width)]:
                    fy = y + lengths["title"] + 10 if field == "notes" else y
                    ids = text(row[field], x, fy, limit, rid, field, background)
                    fields[field] = {
                        "state": "legible" if row[field] else "not_printed",
                        "polygon": rect(x, fy, limit, max(1, len(ids)) * spacing),
                        "frame": "original",
                        "line_ids": ids,
                    }
                fields["date"] = {
                    "state": "legible",
                    "polygon": date_polygon,
                    "frame": "original",
                    "line_ids": date_lines,
                }
                row.update(fields=fields, row_polygon=rect(40, y - 8, 1520, row_height))
                rows.append(row)
                members.append(rid)
                y += row_height + 9
            days.append(
                {"id": day_id, "date": day, "line_ids": date_lines, "appointment_ids": members}
            )
            y += 35
    height = max(2400, y + 60)
    image = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(image)
    for rectangle, color in backgrounds:
        draw.rectangle(rectangle, fill=color)
    for line in lines:
        draw.text(tuple(line["origin"]), line["text"], font=font, fill="black")
    if kind == "unusable":
        # No readable underlying schedule or hidden full-text target exists.
        for _ in range(120):
            x, y = rng.randrange(width), rng.randrange(height)
            draw.ellipse((x, y, x + rng.randrange(5, 80), y + rng.randrange(5, 35)), fill="#d8d8d8")
    return image, {
        "schema_version": VERSION,
        "synthetic": True,
        "independent_final_test": False,
        "input_kind": kind,
        "column_order": [field for field, _, _ in columns] if kind == "schedule" else [],
        "seed": SEED + index,
        "group": f"synthetic-v{VERSION}-{index}",
        "font_size": font_size,
        "font_sha256": hashlib.sha256(font_path.read_bytes()).hexdigest(),
        "width": width,
        "height": height,
        "appointments": rows,
        "days": days,
        "lines": lines,
    }


def validate(image, labels, font_path):
    """Compare each complete label with actual glyph pixels and field boundaries."""
    if image.size != (labels["width"], labels["height"]):
        raise ValueError("Image dimensions changed without transforming labels")
    if labels["font_sha256"] != hashlib.sha256(font_path.read_bytes()).hexdigest():
        raise ValueError("Font identity changed")
    font = ImageFont.truetype(str(font_path), labels["font_size"])
    by_id = {line["id"]: line for line in labels["lines"]}
    if len(by_id) != len(labels["lines"]):
        raise ValueError("Duplicated line identity")
    seen = set()
    for line in labels["lines"]:
        if line["state"] != "legible":
            raise ValueError("Base renderer only emits complete readable lines")
        box = bounds(line["polygon"])
        key = (line["text"], box)
        if key in seen:
            raise ValueError("Shared text must be drawn and labeled once")
        seen.add(key)
        if not line["text"] or not (
            0 <= box[0] < box[2] <= image.width and 0 <= box[1] < box[3] <= image.height
        ):
            raise ValueError("A complete text label is empty or clipped")
        expected = Image.new("RGB", (box[2] - box[0], box[3] - box[1]), line["background"])
        origin = (line["origin"][0] - box[0], line["origin"][1] - box[1])
        ImageDraw.Draw(expected).text(origin, line["text"], font=font, fill="black")
        if ImageChops.difference(expected, image.crop(box)).getbbox():
            raise ValueError("Rendered pixels differ from the complete text label")
    date_ids = set()
    for day in labels["days"]:
        date_ids.update(day["line_ids"])
    if date_ids != {line["id"] for line in labels["lines"] if line["field"] == "date"}:
        raise ValueError("Shared date evidence differs from day boundaries")
    for row in labels["appointments"]:
        for name, field in row["fields"].items():
            if bool(row[name]) != (field["state"] == "legible") or bool(row[name]) != bool(
                field["line_ids"]
            ):
                raise ValueError("Blank field state or text evidence is contradictory")
            outer = bounds(field["polygon"])
            if name != "date":
                expected_text = wrap(row[name], font, outer[2] - outer[0])
                if [by_id[identifier]["text"] for identifier in field["line_ids"]] != expected_text:
                    raise ValueError("Appointment value differs from its printed evidence")
            for identifier in field["line_ids"]:
                line = by_id[identifier]
                inner = bounds(line["polygon"])
                if not (
                    outer[0] <= inner[0] < inner[2] <= outer[2]
                    and outer[1] <= inner[1] < inner[3] <= outer[3]
                ):
                    raise ValueError("Text extends outside its field")
                if name == "date" and (identifier not in date_ids or line["text"] != row["date"]):
                    raise ValueError("Appointment refers to the wrong day heading")
                if name != "date" and (
                    line["appointment_id"] != row["id"] or line["field"] != name
                ):
                    raise ValueError("Field refers to a neighboring row or column")
    if labels["input_kind"] != "schedule" and (labels["appointments"] or labels["days"]):
        raise ValueError("Negative input contains appointment targets")


def generate(output, font_path, count=200):
    if not 1 <= count <= 10000:
        raise ValueError("Use 1–10000 synthetic inputs per versioned export")
    output.mkdir(parents=True, exist_ok=False)
    records = []
    for index in range(count):
        image, labels = render(index, font_path)
        validate(image, labels, font_path)
        name = f"plan-{index:03}"
        path = output / f"{name}.png"
        image.save(path)
        with Image.open(path) as saved:
            validate(saved.convert("RGB"), labels, font_path)
        labels["image_file"] = path.name
        labels["image_sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        (output / f"{name}.json").write_text(
            json.dumps(labels, ensure_ascii=False, indent=2) + "\n"
        )
        records.append(
            {
                "id": name,
                "group": labels["group"],
                "input_kind": labels["input_kind"],
                "seed": SEED + index,
                "image_sha256": labels["image_sha256"],
                "labels_sha256": hashlib.sha256((output / f"{name}.json").read_bytes()).hexdigest(),
            }
        )
    manifest = {
        "schema_version": VERSION,
        "synthetic": True,
        "seed": SEED,
        "count": count,
        "font_sha256": hashlib.sha256(font_path.read_bytes()).hexdigest(),
        "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "python": platform.python_version(),
        "pillow": PILLOW_VERSION,
        "pixel_validation": "all complete lines, before and after lossless export",
        "purpose": "training_and_robustness_only",
        "records": records,
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--font", type=Path)
    parser.add_argument("--count", type=int, default=200)
    args = parser.parse_args()
    font_path = args.font or next(
        p
        for p in [
            Path("/System/Library/Fonts/Supplemental/Arial.ttf"),
            Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
        ]
        if p.exists()
    )
    print(
        json.dumps(
            {"generated": generate(args.output, font_path, args.count)["count"], "synthetic": True}
        )
    )
