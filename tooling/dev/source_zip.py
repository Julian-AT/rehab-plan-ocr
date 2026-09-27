"""Create deterministic source archives and verify their complete Git provenance."""

import argparse
import hashlib
import json
import stat
import tempfile
import zipfile
from pathlib import Path

import source_tree as source

PREFIX = "rehab-plan-ocr/"
STAMP = (1980, 1, 1, 0, 0, 0)


def create(root=source.ROOT, output=None):
    if not source.checkout(root):
        raise ValueError("Packaging requires a clean committed Git checkout")
    if source.git(root, "status", "--porcelain", "--untracked-files=all"):
        raise ValueError("Packaging requires a clean committed tree, including untracked source")
    commit = source.git(root, "rev-parse", "HEAD").decode().strip()
    entries, contents, files = [], {}, []
    for record in source.git(root, "ls-tree", "-rz", "--full-tree", commit).split(b"\0"):
        if not record:
            continue
        metadata, name = record.split(b"\t", 1)
        mode, kind, oid = metadata.decode().split()
        name = name.decode()
        source.safe_path(name)
        if kind != "blob" or mode not in {"100644", "100755"}:
            raise ValueError(f"Unexpected symlink or submodule: {name}")
        entry = {"path": name, "mode": mode, "oid": oid}
        entries.append(entry)
        if name in source.EXCLUDED:
            continue
        if not source.allowed(name):
            raise ValueError(f"Prohibited tracked artifact: {name}")
        data = source.git(root, "cat-file", "blob", oid)
        path = source.regular(root, name)
        if path.read_bytes() != data or bool(path.stat().st_mode & 0o111) != (mode == "100755"):
            raise ValueError(f"Working tree differs from commit: {name}")
        contents[name] = data
        files.append({**entry, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
    value = {
        "schema_version": 1,
        "commit": commit,
        "commit_object": source.git(root, "cat-file", "commit", commit).decode(),
        "git_tree": sorted(entries, key=lambda e: e["path"]),
        "files": sorted(files, key=lambda e: e["path"]),
    }
    source.validate_manifest(value)
    contents[source.MANIFEST] = (
        json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n"
    ).encode()
    modes = {entry["path"]: int(entry["mode"][-3:], 8) for entry in files}
    output = output or root / ".local/submissions" / f"rehab-plan-ocr-{commit}.zip"
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=output.parent, suffix=".zip") as temporary:
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_STORED) as archive:
            for name, data in sorted(contents.items()):
                info = zipfile.ZipInfo(PREFIX + name, date_time=STAMP)
                info.create_system = 3
                info.external_attr = (stat.S_IFREG | modes.get(name, 0o644)) << 16
                archive.writestr(info, data)
        temporary.flush()
        verify(Path(temporary.name))
        data = Path(temporary.name).read_bytes()
        if output.exists():
            if output.is_symlink() or output.read_bytes() != data:
                raise ValueError(
                    "Existing submission differs; preserve it and use another destination"
                )
        else:
            with output.open("xb") as stream:
                stream.write(data)
    checksum = hashlib.sha256(data).hexdigest()
    sidecar = output.with_suffix(".zip.sha256")
    expected = f"{checksum}  {output.name}\n"
    if sidecar.exists():
        if sidecar.is_symlink() or sidecar.read_text() != expected:
            raise ValueError("Existing checksum differs")
    else:
        with sidecar.open("x") as stream:
            stream.write(expected)
    return output, checksum


def verify(path):
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        names = [entry.filename for entry in entries]
        if names != sorted(set(names)) or archive.comment:
            raise ValueError("Duplicate or unsorted ZIP entries, or unexpected comment")
        for entry in entries:
            source.safe_path(entry.filename)
            relative = entry.filename.removeprefix(PREFIX)
            if (
                not entry.filename.startswith(PREFIX)
                or (relative != source.MANIFEST and not source.allowed(relative))
                or entry.create_system != 3
                or entry.date_time != STAMP
                or entry.compress_type != zipfile.ZIP_STORED
                or entry.extra
                or entry.comment
                or entry.flag_bits & 1
                or entry.file_size > 100 * 1024**2
                or entry.external_attr >> 16 not in {stat.S_IFREG | 0o644, stat.S_IFREG | 0o755}
            ):
                raise ValueError(f"Unexpected ZIP entry: {entry.filename}")
        value = json.loads(archive.read(PREFIX + source.MANIFEST))
        files = source.validate_manifest(value)
        if set(names) != {PREFIX + source.MANIFEST, *(PREFIX + e["path"] for e in files)}:
            raise ValueError("ZIP file inventory differs from manifest")
        if archive.getinfo(PREFIX + source.MANIFEST).external_attr >> 16 != stat.S_IFREG | 0o644:
            raise ValueError("Unexpected manifest permissions")
        for entry in files:
            item = archive.getinfo(PREFIX + entry["path"])
            if stat.S_IMODE(item.external_attr >> 16) != int(entry["mode"][-3:], 8):
                raise ValueError(f"Source permission mismatch: {entry['path']}")
            source.verify_bytes(entry, archive.read(item))
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["create", "verify", "directory"])
    parser.add_argument("path", type=Path, nargs="?")
    args = parser.parse_args()
    if args.action == "create":
        path, checksum = create()
        print(f"{path}\nSHA-256: {checksum}")
    else:
        if args.action == "verify" and args.path is None:
            parser.error("verify requires an archive path")
        value = (
            verify(args.path)
            if args.action == "verify"
            else source.verify_directory(args.path or source.ROOT)
        )
        print(f"Verified {len(value['files'])} files from commit {value['commit']}")


if __name__ == "__main__":
    main()
