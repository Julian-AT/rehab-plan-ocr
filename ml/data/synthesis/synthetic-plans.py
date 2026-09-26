# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow==12.1.0"]
# ///
"""Generate 200 reproducible, wholly invented clinic tables and exact polygons.

Names, rooms and treatments are sampled independently. Synthetics are training
or robustness data only, never evidence of accuracy on original clinic photos.
"""

import argparse
import hashlib
import json
import random
from datetime import date, timedelta
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

VERSION = 1
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


def render(index, font_path):
    rng = random.Random(SEED + index)
    width, height = 1600, 2400
    image = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(str(font_path), 24)
    day = (date(2030, 1, 1) + timedelta(days=index)).isoformat()
    lines, rows = [], []

    def text(value, x, y, max_width, row, field):
        words = value.split()
        wrapped = []
        for word in words:
            if not wrapped or draw.textlength(wrapped[-1] + " " + word, font=font) > max_width:
                wrapped.append(word)
            else:
                wrapped[-1] += " " + word
        for n, line in enumerate(wrapped):
            cy = y + n * 31
            draw.text((x, cy), line, font=font, fill="black")
            box = draw.textbbox((x, cy), line, font=font)
            lines.append(
                {
                    "id": f"{row}-{field}-{n}",
                    "appointment_id": row,
                    "field": field,
                    "text": line,
                    "state": "legible",
                    "polygon": rect(box[0], box[1], box[2] - box[0], box[3] - box[1]),
                }
            )
        return len(wrapped) * 31

    draw.text((60, 40), "ERFUNDENER TESTPLAN · keine Patientendaten", font=font, fill="black")
    for label, x in [
        ("Uhrzeit", 60),
        ("Therapie", 350),
        ("Raum", 930),
        ("Therapeut", 1240),
    ]:
        draw.text((x, 160), label, font=font, fill="black")
    count = rng.randint(8, 13)
    for n in range(count):
        rid = f"synthetic-{index:03}-{n:02}"
        start = 450 + n * 30
        row = {
            "id": rid,
            "date": day,
            "start": f"{start // 60:02}:{start % 60:02}",
            "end": f"{(start + 20) // 60:02}:{(start + 20) % 60:02}",
            "title": rng.choice(TITLES),
            "location": rng.choice(ROOMS),
            "therapist": rng.choice(NAMES),
            "notes": "",
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
            row.update({k: rows[-1][k] for k in ["start", "end", "title", "location", "therapist"]})
        if n == 5 and index % 3 == 0:
            row["start"] = rows[-1]["start"]
        if n == 1:
            row["notes"] = "bitte feste Schuhe mitbringen"
        y = 230 + n * 165
        if n % 2 == 0:
            draw.rectangle((40, y - 8, 1560, y + 148), fill="#eeeeee")
        fields = {}
        for field, x, limit in [
            ("start", 60, 98),
            ("end", 180, 110),
            ("title", 350, 540),
            ("location", 930, 270),
            ("therapist", 1240, 300),
            ("notes", 350, 540),
        ]:
            fy = y + 90 if field == "notes" else y
            used = text(row[field], x, fy, limit, rid, field)
            fields[field] = {
                "state": "legible" if row[field] else "not_printed",
                "polygon": rect(x, fy, limit, max(30, used)),
                "frame": "original",
            }
        # Exact date labels are shared heading evidence, with row-specific links.
        before = len(lines)
        text(day, 60, 95, 400, rid, "date")
        fields["date"] = {
            "state": "legible",
            "polygon": lines[before]["polygon"],
            "frame": "original",
        }
        row.update(fields=fields, row_polygon=rect(40, y - 8, 1520, 156))
        rows.append(row)
    return image, {
        "schema_version": VERSION,
        "synthetic": True,
        "independent_final_test": False,
        "seed": SEED + index,
        "width": width,
        "height": height,
        "appointments": rows,
        "lines": lines,
    }


def generate(output, font_path, count=200):
    output.mkdir(parents=True, exist_ok=False)
    records = []
    for index in range(count):
        image, labels = render(index, font_path)
        name = f"plan-{index:03}"
        image.save(output / f"{name}.jpg", quality=90)
        labels["image_sha256"] = hashlib.sha256((output / f"{name}.jpg").read_bytes()).hexdigest()
        (output / f"{name}.json").write_text(
            json.dumps(labels, ensure_ascii=False, indent=2) + "\n"
        )
        records.append(
            {
                "id": name,
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
        "purpose": "training_and_robustness_only",
        "records": records,
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--font", type=Path)
    args = parser.parse_args()
    font_path = args.font or next(
        p
        for p in [
            Path("/System/Library/Fonts/Supplemental/Arial.ttf"),
            Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
        ]
        if p.exists()
    )
    print(json.dumps({"generated": generate(args.output, font_path)["count"], "synthetic": True}))
