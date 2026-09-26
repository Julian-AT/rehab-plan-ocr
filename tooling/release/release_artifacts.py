"""Reserve immutable release destinations and match binaries to retained dSYMs."""

import argparse
import datetime
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ARCHIVE_NAME = "Laßnitzhöhe.xcarchive"


def run(*args):
    return subprocess.check_output(args, stderr=subprocess.PIPE)


def run_path(value, root=ROOT):
    root = root.resolve()
    value = Path(value)
    path = value if value.is_absolute() else root / value
    if ".." in path.parts or not path.is_relative_to(root / ".local/releases"):
        raise ValueError("RELEASE_RUN must be a new child of .local/releases")
    relative = path.relative_to(root / ".local/releases")
    if len(relative.parts) != 1:
        raise ValueError("RELEASE_RUN must name exactly one release directory")
    for parent in [root / ".local", root / ".local/releases", path]:
        if parent.is_symlink():
            raise ValueError("Release storage must not traverse symbolic links")
    return path


def write_new(path, content):
    # Exclusive creation also rejects dangling symbolic links and concurrent writers.
    with path.open("xb") as output:
        os.fchmod(output.fileno(), 0o600)
        output.write(content)
        output.flush()
        os.fsync(output.fileno())


def reserve(value, *, archive=None, root=ROOT):
    path = run_path(value, root)
    source = Path(archive).resolve(strict=True) if archive is not None else path / ARCHIVE_NAME
    if archive is not None and not source.is_dir():
        raise ValueError("Explicit source archive is not a directory")
    revision = run("git", "-C", str(root), "rev-parse", "HEAD").decode().strip()
    dirty = bool(run("git", "-C", str(root), "status", "--porcelain", "--untracked-files=no"))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.mkdir(mode=0o700)  # Existing, failed and completed runs are never reused.
    record = {
        "schema_version": 1,
        "created_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "reservation_checkout_commit": revision,
        "reservation_checkout_dirty": dirty,
        "archive_source_commit": revision if archive is None else None,
        "archive_source_dirty": dirty if archive is None else None,
        "archive": str(source),
        "source_kind": "explicit-existing-archive" if archive is not None else "new-archive",
    }
    write_new(path / "release-run.json", (json.dumps(record, indent=2) + "\n").encode())
    return source


def load(value, root=ROOT):
    path = run_path(value, root)
    marker = path / "release-run.json"
    if marker.is_symlink():
        raise ValueError("Release provenance must not be a symbolic link")
    record = json.loads(marker.read_text())
    if record.get("schema_version") != 1:
        raise ValueError("Unsupported release provenance")
    source = Path(record["archive"])
    if record["source_kind"] == "new-archive":
        if source != path / ARCHIVE_NAME or source.is_symlink():
            raise ValueError("New archive escaped its reserved release directory")
    elif record["source_kind"] != "explicit-existing-archive":
        raise ValueError("Unknown release source kind")
    if not source.is_absolute() or not source.is_dir():
        raise ValueError("Reserved archive is missing")
    for name in ["Laßnitzhöhe.ipa", "package-verification.json", ".packaging.lock"]:
        if (path / name).exists() or (path / name).is_symlink():
            raise ValueError("Release output already exists; preserve it and select a new run")
    return path, source, record


def application(archive):
    info = plistlib.loads((archive / "Info.plist").read_bytes())
    relative = Path(info["ApplicationProperties"]["ApplicationPath"])
    products = (archive / "Products").resolve()
    app = products / relative
    if (
        relative.is_absolute()
        or ".." in relative.parts
        or not app.resolve().is_relative_to(products)
    ):
        raise ValueError("Archive application path escapes Products")
    if not app.is_dir():
        raise ValueError("Archive application is missing")
    return app


def sha(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def uuids(path, runner=run):
    value = runner("xcrun", "dwarfdump", "--uuid", str(path)).decode()
    result = re.findall(r"^UUID: ([A-Fa-f0-9-]{36}) \(([^)]+)\)", value, re.MULTILINE)
    if not result or len(result) != len(set(result)):
        raise ValueError("Binary or dSYM has missing or duplicate UUIDs")
    return sorted((identity.upper(), architecture) for identity, architecture in result)


def symbols(archive, app, runner=run):
    candidates = []
    for dwarf in sorted((archive / "dSYMs").glob("*.dSYM/Contents/Resources/DWARF/*")):
        if dwarf.is_file():
            if not dwarf.resolve().is_relative_to(archive.resolve()):
                raise ValueError("dSYM escapes the retained archive")
            candidates.append((dwarf, uuids(dwarf, runner)))
    result = []
    for component in [app, *sorted(app.glob("PlugIns/*.appex"))]:
        info = plistlib.loads((component / "Info.plist").read_bytes())
        name = info["CFBundleExecutable"]
        if Path(name).name != name:
            raise ValueError("Invalid executable name in archived bundle")
        executable = component / name
        if not executable.resolve().is_relative_to(archive.resolve()):
            raise ValueError("Executable escapes the retained archive")
        identity = uuids(executable, runner)
        matches = [dwarf for dwarf, candidate in candidates if candidate == identity]
        if len(matches) != 1:
            raise ValueError(f"Expected one matching dSYM for {info['CFBundleIdentifier']}")
        dwarf = matches[0]
        result.append(
            {
                "bundle": info["CFBundleIdentifier"],
                "uuids": [{"uuid": value, "architecture": arch} for value, arch in identity],
                "binary": str(executable.relative_to(archive)),
                "binary_sha256": sha(executable),
                "dwarf": str(dwarf.relative_to(archive)),
                "dwarf_sha256": sha(dwarf),
            }
        )
    return result


def publish(source, destination):
    with source.open("rb") as data, destination.open("xb") as output:
        os.fchmod(output.fileno(), 0o600)
        shutil.copyfileobj(data, output)
        output.flush()
        os.fsync(output.fileno())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", help="New path below .local/releases")
    parser.add_argument("--archive", type=Path, help="Explicit historical archive to read")
    args = parser.parse_args()
    print(reserve(args.run, archive=args.archive))


if __name__ == "__main__":
    main()
