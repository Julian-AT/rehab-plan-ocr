"""Compare copied native app/App Group data without touching a device or backup DB."""

import argparse
import datetime
import hashlib
import json
import os
import plistlib
import shutil
import sqlite3
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SUPPORT = Path("App/Library/Application Support/at.rehakalender.personal")
PREFERENCES = Path("App/Library/Preferences/at.rehakalender.personal.plist")
SIDECARS = {"ledger.sqlite", "ledger.sqlite-wal", "ledger.sqlite-shm", "ledger.sqlite-journal"}
NATIVE_TABLES = {
    "scans",
    "imports",
    "operations",
    "schedules",
    "settings",
    "failures",
    "intakes",
    "import_batches",
    "batch_operations",
    "plans",
    "plan_pages",
    "processing_attempts",
    "plan_acceptances",
    "event_mutations",
    "owned_events",
}


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def typed(value):
    if value is None:
        return ["null"]
    if isinstance(value, bytes):
        return ["bytes", value.hex()]
    if isinstance(value, datetime.datetime):
        return ["datetime", value.isoformat()]
    if isinstance(value, float):
        return ["float", value.hex()]
    if isinstance(value, dict):
        return ["dict", [[key, typed(item)] for key, item in sorted(value.items())]]
    if isinstance(value, (list, tuple)):
        return ["list", [typed(item) for item in value]]
    if type(value) not in {str, int, bool}:
        raise ValueError("Unsupported persisted value type")
    return [type(value).__name__, value]


def content_hash(value):
    return hashlib.sha256(
        json.dumps(typed(value), ensure_ascii=True, separators=(",", ":")).encode()
    ).hexdigest()


def inventory(root):
    if root.is_symlink() or not root.is_dir():
        raise ValueError("Expected an actual copied container directory")
    files = {}
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise ValueError("Copied containers must not contain symlinks")
        if path.is_dir():
            continue
        if not path.is_file():
            raise ValueError("Unsupported special file in copied container")
        before = path.stat()
        value = digest(path)
        after = path.stat()
        if (before.st_size, before.st_mtime_ns, before.st_ino) != (
            after.st_size,
            after.st_mtime_ns,
            after.st_ino,
        ):
            raise ValueError("Copied data changed while being read")
        files[path.relative_to(root).as_posix()] = {"bytes": after.st_size, "sha256": value}
    return files


def quote(name):
    return '"' + name.replace('"', '""') + '"'


def database(root, projection=None):
    source = root / SUPPORT
    if not (source / "ledger.sqlite").is_file():
        raise ValueError("Copied app database is missing")
    # SQLite may create/update SHM even for a read-only WAL connection. All such
    # work happens in a disposable copy, never inside the original backup.
    with tempfile.TemporaryDirectory(prefix="reha-persistence-db-") as directory:
        temporary = Path(directory)
        for name in SIDECARS:
            if (source / name).is_file():
                shutil.copyfile(source / name, temporary / name)
        connection = sqlite3.connect((temporary / "ledger.sqlite").as_uri() + "?mode=ro", uri=True)
        try:
            connection.execute("PRAGMA query_only=ON")
            connection.execute("BEGIN")
            integrity = [row[0] for row in connection.execute("PRAGMA integrity_check")]
            if integrity != ["ok"] or connection.execute("PRAGMA foreign_key_check").fetchall():
                raise ValueError("Copied database integrity or foreign keys failed")
            schema = connection.execute(
                "SELECT type,name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name"
            ).fetchall()
            tables = {}
            for (name,) in connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
            ):
                columns = [
                    list(row[1:]) for row in connection.execute(f"PRAGMA table_info({quote(name)})")
                ]
                selected = (
                    projection.get(name, {}).get("columns", columns) if projection else columns
                )
                available = {column[0]: column for column in columns}
                if any(available.get(column[0]) != column for column in selected):
                    tables[name] = {"columns": columns, "projection_compatible": False}
                    continue
                query = ",".join(quote(column[0]) for column in selected)
                rows = sorted(
                    content_hash(row)
                    for row in connection.execute(f"SELECT {query} FROM {quote(name)}")
                )
                tables[name] = dict(columns=selected, rows=len(rows), sha256=content_hash(rows))
            version = connection.execute("PRAGMA user_version").fetchone()[0]
            if version not in {8, 9, 10, 11} or not NATIVE_TABLES.issubset(tables):
                raise ValueError("Expected the native schema 8–11 with all persistent tables")
            return dict(
                integrity="ok",
                schema_version=version,
                schema_sha256=content_hash(schema),
                tables=tables,
            )
        finally:
            connection.close()


def snapshot(root):
    for name in ("App/Documents", "AgendaGroup", "IntakeGroup"):
        if not (root / name).is_dir():
            raise ValueError(f"Required copied container is missing: {name}")
    files = inventory(root)
    preferences = plistlib.loads((root / PREFERENCES).read_bytes())
    if not isinstance(preferences, dict):
        raise ValueError("App preferences must be a dictionary")
    result = dict(
        schema_version=1,
        kind="copied-native-persistence",
        files=files,
        database=database(root),
        preferences={key: content_hash(value) for key, value in sorted(preferences.items())},
        tool_sha256=digest(Path(__file__)),
        device_capture_completeness_verified=False,
    )
    if inventory(root) != files:
        raise ValueError("Copied containers changed during snapshot")
    return result


def durable(name):
    path = Path(name)
    if name.startswith(SUPPORT.as_posix() + "/"):
        return path.parent != SUPPORT or path.name not in SIDECARS
    return name.startswith(("App/Documents/", "AgendaGroup/", "IntakeGroup/"))


def equivalent_file(before, after):
    if before.suffix == ".json":
        return content_hash(json.loads(before.read_text())) == content_hash(
            json.loads(after.read_text())
        )
    if before.suffix == ".plist":
        return content_hash(plistlib.loads(before.read_bytes())) == content_hash(
            plistlib.loads(after.read_bytes())
        )
    return False


def compare(before, expected, after):
    if expected.get("schema_version") != 1 or expected.get("kind") != "copied-native-persistence":
        raise ValueError("Unknown persistence snapshot")
    original = snapshot(before)
    if original != expected:
        raise ValueError("Original backup or snapshot tool changed; do not overwrite its evidence")
    current = snapshot(after)
    projected = database(after, original["database"]["tables"])
    tables = {
        name: value == projected["tables"].get(name)
        for name, value in original["database"]["tables"].items()
    }
    changed_preferences = [
        key
        for key, value in original["preferences"].items()
        if current["preferences"].get(key) != value
    ]
    added_preferences = sorted(set(current["preferences"]) - set(original["preferences"]))
    files = {}
    for name, metadata in original["files"].items():
        if not durable(name):
            continue
        if name not in current["files"]:
            state = "missing"
        elif metadata == current["files"][name]:
            state = "identical"
        else:
            try:
                state = (
                    "same_content" if equivalent_file(before / name, after / name) else "changed"
                )
            except (ValueError, plistlib.InvalidFileException):
                state = "changed"
        files[name] = state
    added_files = sorted(
        name for name in set(current["files"]) - set(original["files"]) if durable(name)
    )
    schema_unchanged = all(
        original["database"][key] == current["database"][key]
        for key in ("schema_version", "schema_sha256")
    )
    preserved = (
        all(tables.values())
        and not changed_preferences
        and all(state in {"identical", "same_content"} for state in files.values())
    )
    if inventory(before) != original["files"] or inventory(after) != current["files"]:
        raise ValueError("Copied containers changed during comparison")
    return dict(
        schema_version=1,
        kind="native-persistence-comparison",
        backup_reverified=True,
        existing_data_preserved=preserved,
        review_required=not preserved
        or not schema_unchanged
        or bool(added_files or added_preferences),
        schema_unchanged=schema_unchanged,
        schema_before=original["database"]["schema_version"],
        schema_after=current["database"]["schema_version"],
        original_table_projections_unchanged=tables,
        added_tables=sorted(
            set(current["database"]["tables"]) - set(original["database"]["tables"])
        ),
        changed_preference_keys=changed_preferences,
        added_preference_keys=added_preferences,
        durable_files=files,
        added_durable_files=added_files,
        original_source_files=sum(
            Path(name).name in {"source.bin", "source.pdf"} for name in files
        ),
        snapshot_before_sha256=content_hash(original),
        snapshot_after_sha256=content_hash(current),
        tool_sha256=digest(Path(__file__)),
        device_update_authorized=False,
    )


def save(path, value):
    path = path.resolve()
    if not path.is_relative_to((ROOT / ".local").resolve()):
        raise ValueError("Persistence evidence must remain below ignored .local storage")
    path.parent.mkdir(parents=True, exist_ok=True)
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as output:
        json.dump(value, output, ensure_ascii=False, indent=2)
        output.write("\n")
        output.flush()
        os.fsync(output.fileno())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    capture = commands.add_parser("snapshot")
    capture.add_argument("--root", type=Path, required=True)
    check = commands.add_parser("compare")
    check.add_argument("--before", type=Path, required=True)
    check.add_argument("--snapshot", type=Path, required=True)
    check.add_argument("--after", type=Path, required=True)
    for command in (capture, check):
        command.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    sources = [args.root] if args.command == "snapshot" else [args.before, args.after]
    if any(args.output.resolve().is_relative_to(source.resolve()) for source in sources):
        raise ValueError("Never write comparison evidence inside a copied source container")
    result = (
        snapshot(args.root.resolve())
        if args.command == "snapshot"
        else compare(
            args.before.resolve(), json.loads(args.snapshot.read_text()), args.after.resolve()
        )
    )
    save(args.output, result)
    print(
        json.dumps(
            {
                "kind": result["kind"],
                "output": str(args.output),
                "review_required": result.get("review_required"),
            }
        )
    )
    if result.get("review_required"):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
