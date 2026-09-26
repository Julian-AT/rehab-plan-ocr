"""Private dataset inventory, verified copies and frozen day grouping.

All outputs are local and ignored by Git. No image content is uploaded.
"""

import argparse
import hashlib
import json
import os
import shutil
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PRIVATE = ROOT / ".local/datasets/private"
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
    if (PRIVATE / "inventory.json").exists():
        raise ValueError("Existing inventory preserved. Use intake.py for a new collection batch.")
    source = Path(source).resolve(strict=True)
    if not source.is_dir():
        raise ValueError("Dataset source must be a directory.")
    entries = []
    for path in sorted(source.rglob("*")):
        if path.is_symlink() or not path.is_file() or path.suffix.lower() not in EXTENSIONS:
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
    """Keep the historical command name, but never remove an original source."""
    path = PRIVATE / "inventory.json"
    inventory_hash = digest(path)
    manifest = json.loads(path.read_text())
    receipt_path = PRIVATE / "copy-receipt.json"
    result = {
        "schema_version": 1,
        "inventory_sha256": inventory_hash,
        "status": "copied_hashes_verified",
        "source_deletions": 0,
        "copies": [
            {key: entry[key] for key in ["filename", "sha256"]} for entry in manifest["entries"]
        ],
    }
    if receipt_path.exists() and json.loads(receipt_path.read_text()) != result:
        raise ValueError("Existing copy receipt differs; preserve it and use a new intake batch.")
    raw = PRIVATE / "raw"
    raw.mkdir(parents=True, exist_ok=True)
    # Validate the complete inventory before publishing any new copy.
    for entry in manifest["entries"]:
        source = Path(entry["source"])
        destination = raw / entry["filename"]
        if destination.name != entry["filename"] or source.is_symlink() or destination.is_symlink():
            raise ValueError("Unsafe dataset path.")
        candidate = source if source.exists() else destination
        if digest(candidate) != entry["sha256"]:
            raise ValueError("Source hash changed; no originals removed.")
        if destination.exists() and digest(destination) != entry["sha256"]:
            raise ValueError("Destination filename collision.")
    for entry in manifest["entries"]:
        source = Path(entry["source"])
        destination = raw / entry["filename"]
        if not destination.exists():
            with tempfile.TemporaryDirectory(prefix=".dataset-copy-", dir=raw) as temporary:
                candidate = Path(temporary) / "image"
                shutil.copy2(source, candidate)
                if digest(candidate) != entry["sha256"]:
                    raise ValueError("Post-copy checksum failed; original preserved.")
                os.link(candidate, destination)  # Publish exclusively; never replace another copy.
        if destination.is_symlink() or digest(destination) != entry["sha256"]:
            raise ValueError("Post-copy checksum failed; original preserved.")
        if source.exists() and (source.is_symlink() or digest(source) != entry["sha256"]):
            raise ValueError("Source changed during copying; changed original preserved.")
    if digest(path) != inventory_hash:
        raise ValueError("Inventory changed during copying; no originals removed.")
    if not receipt_path.exists():
        with tempfile.TemporaryDirectory(prefix=".dataset-receipt-", dir=PRIVATE) as temporary:
            receipt = Path(temporary) / "receipt.json"
            receipt.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
            os.link(receipt, receipt_path)  # Historical inventories and receipts remain untouched.
    elif json.loads(receipt_path.read_text()) != result:
        raise ValueError("Copy receipt changed during copying; existing receipt preserved.")
    print(f"Copied and hash-verified {len(manifest['entries'])} images. No source files removed.")


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
                raise ValueError("Capture IDs must be unique safe filenames within a day.")
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
                if source_hash not in hashes or ownership.get(source_hash, owner) != owner:
                    raise ValueError("Each source hash must belong to exactly one day and page.")
                ownership[source_hash] = owner
                assigned.add(source_hash)
                day_hashes.add(source_hash)
        normalized[day] = {"document_hashes": sorted(day_hashes), "captures": captures}
    if assigned != hashes:
        raise ValueError("Every inventoried source hash must be assigned before freezing.")
    return normalized


def freeze(grouping):
    raise ValueError(
        "Legacy day-only grouping cannot prove overlap isolation. Confirm schema-2 "
        "source relationships in the reference editor, then run reference-data.py freeze. "
        "All previously inspected photos remain development data; no final holdout."
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("inventory").add_argument(
        "source", help="Exact user-provided dataset directory; no movement"
    )
    sub.add_parser(
        "relocate", help="Copy inventoried images without removing originals (legacy name)"
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
