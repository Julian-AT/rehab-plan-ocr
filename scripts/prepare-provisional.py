"""Prepare reviewable per-image references; explored images are development data.

Predictions seed drafts only. No reference, page relationship, or accuracy metric
is verified by this script. Shared observed dates form conservative review groups.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path

def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")

def prepare(baseline, conversion, output):
    source = json.loads(conversion.read_text())
    runs = [json.loads(p.read_text()) for p in sorted(baseline.glob("document-*/run.json"))]
    if len(runs) != len(source["entries"]):
        raise ValueError("Every converted image needs a retained run.")
    if (output / "split.json").exists() or (output / "inventory.json").exists():
        raise ValueError("Existing inventory/grouping preserved; choose a new destination.")
    dates = [{s["date"] for s in r.get("sections", []) if s["date"]} for r in runs]
    parents = list(range(len(runs)))
    def root(i):
        while parents[i] != i:
            i = parents[i]
        return i
    for i in range(len(runs)):
        for j in range(i):
            if dates[i] & dates[j]:
                parents[root(i)] = root(j)
    roots = sorted({root(i) for i in range(len(runs))})
    groups, inventory, references = {}, [], []
    raw = output / "raw"
    raw.mkdir(parents=True, exist_ok=True)
    for i, run in enumerate(runs):
        h = run["document"]["source_hash"]
        converted = next(e for e in source["entries"] if e["png"]["sha256"] == h)
        image = Path(converted["png"]["path"])
        if hashlib.file_digest(image.open("rb"), "sha256").hexdigest() != h:
            raise ValueError("Converted source checksum mismatch.")
        dest = raw / image.name
        # Same filesystem hard link preserves bytes without another full image copy.
        os.link(image, dest)
        group = f"development-{roots.index(root(i))+1:02}"
        inventory.append({"filename": image.name, "sha256": h, "bytes": image.stat().st_size, "original_sha256": converted["source_sha256"]})
        g = groups.setdefault(group, {"split": "development", "fold": None, "document_hashes": [], "captures": [], "grouping_verified": False})
        g["document_hashes"].append(h)
        g["captures"].append({"id": f"photo-{i+1:02}", "pages": {"unverified-page": h}})
        reference = {"schema_version": 1, "day_id": group, "document_hashes": [h], "verified": False, "reviewed_at": None, "split": "development", "appointments": run["appointments"], "uncertainty_notes": ["Provisional OCR seed: compare every appointment, field and omission with the image.", "Page/capture relationships require review before group-level verification."]}
        write(output / "labels" / "provisional" / f"{h}.json", reference)
        references.append({"sha256": h, "filename": image.name, "day_id": group, "path": f"labels/provisional/{h}.json", "verified": False})
    write(output / "inventory.json", {"schema_version": 1, "status": "development_derivatives", "entries": inventory})
    write(output / "split.json", {"schema_version": 2, "kind": "previously_explored_development", "grouping_verified": False, "final_holdout_available": False, "days": groups})
    write(output / "provisional-index.json", {"schema_version": 1, "references": references})
    return {"images": len(runs), "provisional_groups": len(groups), "verified_references": 0}

if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("baseline", type=Path)
    p.add_argument("conversion", type=Path)
    p.add_argument("--output", type=Path, default=Path("data/private"))
    a = p.parse_args()
    print(json.dumps(prepare(a.baseline, a.conversion, a.output)))
