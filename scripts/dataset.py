"""Private dataset inventory, hash-preserving relocation and frozen day grouping.

All outputs are local and ignored by Git. No image content is uploaded.
"""

import argparse
import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / "data/private"
EXTENSIONS = {".jpg", ".jpeg", ".png", ".heic", ".heif"}


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".part")
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    temp.replace(path)


def inventory(source):
    source = Path(source).resolve(strict=True)
    if not source.is_dir():
        raise ValueError("Dataset source must be a directory.")
    entries = []
    for path in sorted(source.rglob("*")):
        if (
            path.is_symlink()
            or not path.is_file()
            or path.suffix.lower() not in EXTENSIONS
        ):
            continue
        entries.append(
            {
                "source": str(path),
                "filename": path.name,
                "sha256": digest(path),
                "bytes": path.stat().st_size,
            }
        )
    if len({e["filename"] for e in entries}) != len(entries):
        raise ValueError(
            "Duplicate filenames in different folders: choose explicit files before relocation. Nothing moved."
        )
    manifest = {
        "schema_version": 1,
        "inventoried_at": datetime.now(timezone.utc).isoformat(),
        "status": "inventoried_not_moved",
        "entries": entries,
    }
    write(PRIVATE / "inventory.json", manifest)
    print(
        f"Inventoried {len(entries)} images; {len({e['sha256'] for e in entries})} unique byte hashes. Nothing moved."
    )


def relocate():
    path = PRIVATE / "inventory.json"
    manifest = json.loads(path.read_text())
    raw = PRIVATE / "raw"
    raw.mkdir(parents=True, exist_ok=True)
    # Validate the whole proposed relocation before changing any file.
    for entry in manifest["entries"]:
        source = Path(entry["source"])
        destination = raw / entry["filename"]
        if destination.name != entry["filename"] or source.is_symlink():
            raise ValueError("Unsafe dataset path.")
        candidate = source if source.exists() else destination
        if digest(candidate) != entry["sha256"]:
            raise ValueError("Source hash changed; nothing further will be moved.")
        if destination.exists() and digest(destination) != entry["sha256"]:
            raise ValueError("Destination filename collision.")
    for entry in manifest["entries"]:
        source = Path(entry["source"])
        destination = raw / entry["filename"]
        if source.resolve() == destination.resolve():
            continue
        if not destination.exists():
            temporary = destination.with_suffix(destination.suffix + ".part")
            shutil.copy2(source, temporary)
            if digest(temporary) != entry["sha256"]:
                temporary.unlink()
                raise ValueError("Post-copy checksum failed; original preserved.")
            temporary.replace(destination)
        if digest(destination) != entry["sha256"]:
            raise ValueError("Post-relocation checksum failed; original preserved.")
        if source.exists():
            source.unlink()
        entry["relocated_verified"] = True
        write(path, manifest)  # resumable after each verified image
    manifest["status"] = "relocated_hashes_verified"
    write(path, manifest)
    print(
        f"Relocated and hash-verified {len(manifest['entries'])} images. Original names and bytes preserved."
    )


def normalize_groups(groups, hashes):
    """Each capture is a complete page set; alternate photos never add appointments."""
    normalized = {}
    ownership = {}
    assigned = set()
    for day, group in groups.items():
        if not day or Path(day).name != day or day in {".", ".."}:
            raise ValueError("Day IDs must be safe filenames.")
        captures = group["captures"]
        page_keys = None
        capture_ids = set()
        day_hashes = set()
        if not captures:
            raise ValueError("Each day needs at least one complete capture.")
        for capture in captures:
            identifier = capture["id"]
            pages = capture["pages"]
            if (
                not identifier
                or Path(identifier).name != identifier
                or identifier in {".", ".."}
                or identifier in capture_ids
            ):
                raise ValueError(
                    "Capture IDs must be unique safe filenames within a day."
                )
            capture_ids.add(identifier)
            if not pages or (page_keys is not None and set(pages) != page_keys):
                raise ValueError(
                    "All captures of a day must include the same explicitly identified pages."
                )
            page_keys = set(pages)
            if len(set(pages.values())) != len(pages):
                raise ValueError("One photo cannot represent two pages.")
            for page, source_hash in pages.items():
                owner = (day, page)
                if (
                    source_hash not in hashes
                    or ownership.get(source_hash, owner) != owner
                ):
                    raise ValueError(
                        "Each source hash must belong to exactly one day and page."
                    )
                ownership[source_hash] = owner
                assigned.add(source_hash)
                day_hashes.add(source_hash)
        normalized[day] = {"document_hashes": sorted(day_hashes), "captures": captures}
    if assigned != hashes:
        raise ValueError(
            "Every inventoried source hash must be assigned before freezing."
        )
    return normalized


def freeze(grouping):
    output = PRIVATE / "split.json"
    if output.exists():
        raise ValueError(
            "Split already frozen. Do not retune by reshuffling held-out days."
        )
    groups = json.loads(Path(grouping).read_text())
    inventory_data = json.loads((PRIVATE / "inventory.json").read_text())
    hashes = {e["sha256"] for e in inventory_data["entries"]}
    if len(groups) != 20:
        raise ValueError(
            "The agreed split requires 20 distinct days (16 development, 4 holdout). Record a scope change before using fewer."
        )
    groups = normalize_groups(groups, hashes)
    seed = "reha-calendar-split-v1"
    ordered = sorted(
        groups, key=lambda day: hashlib.sha256(f"{seed}:{day}".encode()).hexdigest()
    )
    days = {
        day: {
            "split": "holdout" if i < 4 else "development",
            "fold": None if i < 4 else (i - 4) % 4,
            **groups[day],
        }
        for i, day in enumerate(ordered)
    }
    result = {
        "schema_version": 2,
        "seed": seed,
        "frozen_at": datetime.now(timezone.utc).isoformat(),
        "days": days,
        "grouping_sha256": digest(Path(grouping)),
        "holdout_used": False,
    }
    write(output, result)
    print(
        "Frozen 16 development days in four grouped folds and four final holdout days."
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("inventory").add_argument(
        "source", help="Exact user-provided dataset directory; no movement"
    )
    sub.add_parser(
        "relocate", help="Move only inventoried image files after checking all hashes"
    )
    sub.add_parser("freeze").add_argument(
        "grouping",
        help="JSON mapping of 20 day IDs to captures: [{id, pages: {page_id: source_sha256}}]",
    )
    args = parser.parse_args()
    if args.command == "inventory":
        inventory(args.source)
    elif args.command == "relocate":
        relocate()
    else:
        freeze(args.grouping)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError) as error:
        raise SystemExit(str(error))
