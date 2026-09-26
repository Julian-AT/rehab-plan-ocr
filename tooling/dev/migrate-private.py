#!/usr/bin/env python3
"""Inventory and relocate project-owned private storage without deleting originals.

The immutable inventory and progress journal remain ignored under .local/. Old
paths become compatibility symlinks so historical references and Git worktrees
continue to resolve. Canonical consumer-path changes are a separate step.
"""

import argparse
import hashlib
import json
import os
import stat
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MOVES = {
    "data/private": ".local/datasets/private",
    "models/private": ".local/models/runtime",
    "artifacts": ".local/runs/legacy",
}


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    with temporary.open("w") as output:
        json.dump(value, output, ensure_ascii=False, indent=2)
        output.write("\n")
        output.flush()
        os.fsync(output.fileno())
    temporary.chmod(0o600)
    temporary.replace(path)


def inventory(root):
    if root.is_symlink() or not root.is_dir():
        raise ValueError(f"Expected an actual storage directory: {root}")
    root = root.resolve()
    entries = {}
    for directory, folders, files in os.walk(root, followlinks=False):
        for name in sorted(folders + files):
            path = Path(directory) / name
            relative = str(path.relative_to(root))
            before = path.lstat()
            if path.is_symlink():
                target = os.readlink(path)
                if not os.path.isabs(target) and not Path(
                    os.path.abspath(path.parent / target)
                ).is_relative_to(root.resolve()):
                    raise ValueError(
                        "External relative symlink needs a relocation mapping; no move performed"
                    )
                entry = {"kind": "symlink", "target": target}
            elif stat.S_ISDIR(before.st_mode):
                entry = {"kind": "directory"}
            elif stat.S_ISREG(before.st_mode):
                with path.open("rb") as source:
                    digest = hashlib.file_digest(source, "sha256").hexdigest()
                after = path.stat()
                if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
                    raise ValueError(
                        "A private file changed during inventory; stop its writer and retry"
                    )
                entry = {"kind": "file", "bytes": before.st_size, "sha256": digest}
            else:
                raise ValueError("Unsupported special file in private storage; no move performed")
            entry["mode"] = stat.S_IMODE(before.st_mode)
            entries[relative] = entry
    return entries


def plan(root, manifest):
    if manifest.exists():
        raise ValueError("Inventory already exists; preserve it and use a new path")
    result = {"schema_version": 1, "root": str(root.resolve()), "moves": {}}
    for source, destination in MOVES.items():
        if (root / destination).exists() or (root / destination).is_symlink():
            raise ValueError(
                "Destination already exists; never merge private collections implicitly"
            )
        entries = inventory(root / source)
        result["moves"][source] = {"destination": destination, "entries": entries}
        print(f"Inventoried {source}: {len(entries)} entries", flush=True)
    write_json(manifest, result)


def apply(root, manifest):
    result = json.loads(manifest.read_text())
    if result.get("root") != str(root.resolve()) or set(result["moves"]) != set(MOVES):
        raise ValueError("Inventory belongs to a different workspace or set of moves")
    for source, destination in MOVES.items():
        if result["moves"][source]["destination"] != destination:
            raise ValueError("Unexpected destination in inventory")
    journal = manifest.with_name(manifest.stem + "-progress.json")
    progress = {"manifest_sha256": hashlib.sha256(manifest.read_bytes()).hexdigest(), "moves": {}}
    if journal.exists():
        saved = json.loads(journal.read_text())
        if saved["manifest_sha256"] != progress["manifest_sha256"]:
            raise ValueError("Progress journal belongs to a different inventory")
        progress = saved
    for source, destination in MOVES.items():
        old, new = root / source, root / destination
        expected = result["moves"][source]["entries"]
        if new.is_symlink() or not new.parent.resolve().is_relative_to(root.resolve()):
            raise ValueError("Destination must be an actual directory within this workspace")
        if progress["moves"].get(source) == "verified":
            if not new.is_dir() or not old.is_symlink() or old.resolve() != new.resolve():
                raise ValueError("Previously verified storage no longer has its expected location")
            # Normal work may add/edit labels, caches or model outputs after the
            # migration. Never roll that work back against a historical snapshot.
            print(f"Already relocated and verified: {source}", flush=True)
            continue
        if not new.exists():
            if inventory(old) != expected:
                raise ValueError(
                    "Private files changed since inventory; no move performed for this directory"
                )
            new.parent.mkdir(parents=True, exist_ok=True)
            # rename is atomic on this workspace volume and requires no second
            # copy of model weights or backups. Cross-volume moves fail safely.
            old.rename(new)
        elif (old.exists() or old.is_symlink()) and (
            not old.is_symlink() or old.resolve() != new.resolve()
        ):
            raise ValueError("Both source and destination exist; refusing to overwrite either")
        if not old.is_symlink():
            old.symlink_to(os.path.relpath(new, old.parent), target_is_directory=True)
        progress["moves"][source] = "moved-awaiting-verification"
        write_json(journal, progress)
        if inventory(new) != expected:
            # Preserve all bytes, including a possible concurrent modification.
            # Restore the old location rather than deleting the unexpected data.
            old.unlink()
            new.rename(old)
            progress["moves"][source] = "restored-after-verification-failure"
            write_json(journal, progress)
            raise ValueError("Post-move verification failed; the original directory was restored")
        progress["moves"][source] = "verified"
        write_json(journal, progress)
        print(f"Verified relocation {source} -> {destination}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["plan", "apply"])
    parser.add_argument(
        "--manifest", type=Path, default=ROOT / ".local/migrations/private-storage.json"
    )
    args = parser.parse_args()
    manifest = args.manifest.resolve()
    if not manifest.is_relative_to(ROOT / ".local"):
        raise ValueError("Private inventories must remain in ignored .local storage")
    (plan if args.action == "plan" else apply)(ROOT, manifest)


if __name__ == "__main__":
    main()
