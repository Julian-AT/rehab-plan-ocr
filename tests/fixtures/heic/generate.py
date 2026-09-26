# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow==12.1.1", "pillow-heif==1.7.0"]
# ///
"""Invented HEIC fixtures: four color quadrants, all orientations, primary image.

Regenerate with: uv run tests/fixtures/heic/generate.py
EXIF must be encoded bytes so libheif also writes the HEIF irot/imir properties.
"""

from pathlib import Path

from PIL import Image
from pillow_heif import register_heif_opener

register_heif_opener()
root = Path(__file__).parent
image = Image.new("RGB", (96, 64))
for box, color in [
    ((0, 0, 48, 32), (240, 20, 20)),
    ((48, 0, 96, 32), (20, 220, 20)),
    ((0, 32, 48, 64), (20, 20, 240)),
    ((48, 32, 96, 64), (230, 220, 20)),
]:
    image.paste(color, box)
for orientation in range(1, 9):
    exif = Image.Exif()
    exif[274] = orientation
    image.save(
        root / f"orientation-{orientation}.heic",
        format="HEIF",
        quality=100,
        exif=exif.tobytes(),
        thumbnails=[16],
    )
image.save(
    root / "multiple-images.heic",
    format="HEIF",
    quality=100,
    save_all=True,
    append_images=[Image.new("RGB", (32, 48), (20, 20, 240))],
    primary_index=1,
)
