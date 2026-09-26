# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow==12.1.1", "pillow-heif==1.7.0"]
# ///
"""Create full-resolution PNGs from private HEIC originals without moving them.

Identical source bytes share one PNG. A manifest records every original and both
hashes. PNG compression is lossless; HEIC HDR is decoded to the OCR pipeline's
8-bit RGB representation. EXIF/XMP are removed; the color profile is retained.
"""

import argparse
import hashlib
import importlib.metadata
import json
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image, ImageOps
from pillow_heif import libheif_info, register_heif_opener

register_heif_opener()


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_json(path, value):
    temporary = path.with_suffix(".part")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(path)


def convert(source, destination):
    with Image.open(source) as image:
        primary_frame = image.tell()
        source_size = list(image.size)
        orientation = image.info.get("original_orientation") or image.getexif().get(274, 1)
        bit_depth = image.info.get("bit_depth", 8)
        profile = image.info.get("icc_profile")
        upright = ImageOps.exif_transpose(image).convert("RGB")
        # A fresh pixel image avoids carrying GPS, EXIF, XMP or text chunks over.
        pixels = Image.frombytes("RGB", upright.size, upright.tobytes())
        temporary = destination.with_suffix(".part")
        pixels.save(temporary, format="PNG", icc_profile=profile)
        with Image.open(temporary) as decoded:
            if decoded.size != pixels.size or decoded.tobytes() != pixels.tobytes():
                raise ValueError("PNG pixel verification failed; originals preserved.")
            if set(decoded.info) - {"icc_profile"}:
                raise ValueError("Unexpected metadata in converted PNG.")
        temporary.replace(destination)
    return {
        "path": str(destination.resolve()),
        "sha256": digest(destination),
        "bytes": destination.stat().st_size,
        "width": pixels.width,
        "height": pixels.height,
        "source_decoded_size": source_size,
        "source_orientation": orientation,
        "source_bit_depth": bit_depth,
        "primary_frame": primary_frame,
        "mode": "RGB",
        "pixel_roundtrip_verified": True,
        "icc_profile_preserved": bool(profile),
    }


def prepare(source, output):
    source = source.resolve(strict=True)
    paths = [
        path
        for path in source.rglob("*")
        if path.is_file() and not path.is_symlink() and path.suffix.lower() in {".heic", ".heif"}
    ]
    if not paths:
        raise ValueError("No HEIC/HEIF originals found.")
    groups = defaultdict(list)
    for path in sorted(paths, key=lambda p: (len(p.name), str(p))):
        groups[digest(path)].append(path)
    # Immutable output directories make accidental overwrites impossible.
    output.mkdir(parents=True, exist_ok=False)
    manifest = {
        "schema_version": 1,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "status": "converting",
        "source_directory": str(source),
        "source_count": len(paths),
        "unique_count": len(groups),
        "versions": {name: importlib.metadata.version(name) for name in ("pillow", "pillow-heif")},
        "libheif": libheif_info(),
        "conversion": "Primary image, upright, full resolution, 8-bit RGB, lossless PNG; no EXIF/XMP.",
        "entries": [],
    }
    write_json(output / "manifest.json", manifest)
    used_names = set()
    for source_hash, aliases in groups.items():
        name = aliases[0].stem + ".png"
        if name.casefold() in used_names:
            name = f"{aliases[0].stem}-{source_hash}.png"
        used_names.add(name.casefold())
        result = convert(aliases[0], output / name)
        if any(digest(path) != source_hash for path in aliases):
            raise ValueError("Original changed during conversion; inspect manifest.")
        manifest["entries"].append(
            {
                "source_sha256": source_hash,
                "sources": [str(path) for path in aliases],
                "originals_unchanged": True,
                "png": result,
            }
        )
        write_json(output / "manifest.json", manifest)
        print(f"Converted {len(manifest['entries'])}/{len(groups)}", flush=True)
    manifest["status"] = "complete"
    write_json(output / "manifest.json", manifest)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path, help="New private output directory")
    args = parser.parse_args()
    result = prepare(args.source, args.output)
    print(
        f"Verified {result['unique_count']} PNGs from {result['source_count']} originals. "
        "Originals preserved."
    )


if __name__ == "__main__":
    main()
