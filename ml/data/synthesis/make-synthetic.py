# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow==12.1.0"]
# ///
"""Create invented printed schedules, never derived from held-out or patient data."""

import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

root = Path(__file__).resolve().parents[3]
out = root / "ml/evaluation/fixtures"
out.mkdir(parents=True, exist_ok=True)
font_path = next(
    p
    for p in [
        Path("/System/Library/Fonts/Supplemental/Arial.ttf"),
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
    ]
    if p.exists()
)
font = ImageFont.truetype(str(font_path), 29)
small = ImageFont.truetype(str(font_path), 22)
heading = ImageFont.truetype(str(font_path), 42)
image = Image.new("RGB", (1400, 1800), "white")
draw = ImageDraw.Draw(image)
draw.text((95, 70), "MUSTER · ERFUNDENE TERMINE", font=small, fill="#55616b")
draw.text((95, 135), "Tagesplan 10.09.2026", font=heading, fill="black")
draw.text((95, 205), "Gedruckt 09.09.2026 16:45", font=small, fill="#333333")
draw.line((95, 275, 1305, 275), fill="#333333", width=2)
draw.text((95, 295), "Zeit", font=small, fill="black")
draw.text((405, 295), "Termin", font=small, fill="black")
draw.text((1120, 295), "Ort", font=small, fill="black")
rows = [
    ("07:30", "08:00", "Frühstück", "Speisesaal"),
    ("08:15", "08:45", "Bewegungstherapie", "Raum A2"),
    ("09:00", "09:20", "Ärztliches Gespräch", "Raum B1"),
    ("10:00", "10:30", "Entspannung", "Raum C3"),
    ("10:00", "10:30", "Entspannung", "Raum C3"),
    ("11:15", None, "Übungen im Wasser", "Raum D4"),
    ("12:00", "12:45", "Mittagessen", "Speisesaal"),
    ("14:00", "14:30", "Pause", ""),
]
for index, (start, end, title, room) in enumerate(rows):
    y = 380 + index * 135
    draw.text((95, y), start + (f" - {end}" if end else ""), font=font, fill="black")
    draw.text((405, y), title, font=font, fill="black")
    draw.text((1120, y), room, font=small, fill="black")
    if index == 1:
        draw.text((405, y + 42), "Bitte feste Schuhe mitbringen", font=small, fill="black")
    draw.line((95, y + 95, 1305, y + 95), fill="#bbbbbb", width=1)
draw.text(
    (95, 1590),
    "Synthetischer Testplan. Keine echten Behandlungsdaten.",
    font=small,
    fill="#333333",
)
draw.text(
    (95, 1640),
    "Eine Endzeit fehlt absichtlich. Wiederholungen sind beabsichtigt.",
    font=small,
    fill="#333333",
)
image.save(out / "synthetic-day.png")
public = root / "public"
public.mkdir(exist_ok=True)
image.save(public / "synthetic-day.png")
variants = root / "artifacts/private/synthetic-variants"
variants.mkdir(parents=True, exist_ok=True)
image.rotate(90, expand=True).save(variants / "rotated.png")
image.rotate(5, fillcolor="white").save(variants / "skewed.png")
image.filter(ImageFilter.GaussianBlur(2)).save(variants / "blurred.png")
ImageEnhance.Contrast(image).enhance(0.2).save(variants / "low-contrast.png")
image.crop((0, 0, 1400, 1100)).save(variants / "cropped.png")
shadow = image.copy()

mask = Image.new("RGB", image.size)
md = ImageDraw.Draw(mask)
for x in range(image.width):
    tone = int(100 + 155 * x / image.width)
    md.line((x, 0, x, image.height), fill=(tone, tone, tone))
ImageChops.multiply(shadow, mask).save(variants / "shadowed.png")
(out / "synthetic-description.json").write_text(
    json.dumps(
        {
            "synthetic": True,
            "day": "2026-09-10",
            "rows": rows,
            "known_missing_end_row": 5,
            "note": "Invented fixture; not a clinic benchmark.",
        },
        ensure_ascii=False,
        indent=2,
    )
)
print("Created one invented day and six local capture variants.")
