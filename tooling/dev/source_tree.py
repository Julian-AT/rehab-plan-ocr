"""Discover source in checkouts and verify the identity of extracted submissions."""

import hashlib
import json
import os
import re
import stat
import subprocess
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = "SOURCE-MANIFEST.json"
ROOTS = {"apps", "packages", "ml", "tooling", "config", "docs", ".github"}
ROOT_FILES = {
    "Makefile",
    "README.md",
    "LICENSE",
    "Cargo.toml",
    "Cargo.lock",
    "rust-toolchain.toml",
    "pyproject.toml",
    "uv.lock",
    ".gitattributes",
    ".gitignore",
    ".python-version",
    ".swift-format",
    ".editorconfig",
}
EXCLUDED = {"AGENTS.md", "CLAUDE.md"}
GENERATED_PREFIXES = ("apps/ios/build",)
FORBIDDEN = {
    ".git",
    ".local",
    ".venv",
    ".tools",
    ".build",
    "__pycache__",
    ".ruff_cache",
    "node_modules",
    "target",
    "xcuserdata",
    ".DS_Store",
    "private",
    ".env",
}
SUFFIXES = {
    ".pyc",
    ".onnx",
    ".gguf",
    ".safetensors",
    ".dylib",
    ".a",
    ".o",
    ".ipa",
    ".sqlite",
    ".sqlite3",
    ".bundle",
    ".zip",
    ".log",
    ".xcodeproj",
    ".xcframework",
    ".app",
    ".xcarchive",
    ".xcresult",
}


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args])


def checkout(root):
    return (root / ".git").exists()


def safe_path(name):
    path = PurePosixPath(name)
    if (
        not name
        or path.is_absolute()
        or str(path) != name
        or "\\" in name
        or any(p in {"", ".", ".."} or ":" in p for p in name.split("/"))
        or any(ord(c) < 32 or ord(c) == 127 for c in name)
    ):
        raise ValueError(f"Unsafe source path: {name!r}")
    return path


def allowed(name):
    path = safe_path(name)
    if any(name == prefix or name.startswith(prefix + "/") for prefix in GENERATED_PREFIXES):
        return False
    return (name in ROOT_FILES or path.parts[0] in ROOTS) and not any(
        part in FORBIDDEN
        or part in EXCLUDED
        or part.startswith(".env")
        or PurePosixPath(part).suffix in SUFFIXES
        for part in path.parts
    )


def regular(root, name):
    path = root
    for part in safe_path(name).parts:
        path = path / part
        if path.is_symlink():
            raise ValueError(f"Unexpected source symlink: {name}")
    if not path.is_file():
        raise ValueError(f"Missing source file: {name}")
    return path


def object_hash(kind, data):
    return hashlib.sha1(f"{kind} {len(data)}\0".encode() + data).hexdigest()


def tree_hash(entries):
    tree = {}
    for entry in entries:
        parts = safe_path(entry["path"]).parts
        parent = tree
        for part in parts[:-1]:
            parent = parent.setdefault(part, {})
            if not isinstance(parent, dict):
                raise ValueError("Conflicting source paths")
        if parts[-1] in parent:
            raise ValueError("Duplicate source path")
        if entry["mode"] not in {"100644", "100755"} or not re.fullmatch(
            "[0-9a-f]{40}", entry["oid"]
        ):
            raise ValueError("Unexpected Git object mode or identity")
        parent[parts[-1]] = (entry["mode"], entry["oid"])

    def digest(folder):
        data = b""
        for name, value in sorted(
            folder.items(), key=lambda v: (v[0] + ("/" if isinstance(v[1], dict) else "")).encode()
        ):
            mode, oid = ("40000", digest(value)) if isinstance(value, dict) else value
            data += mode.encode() + b" " + name.encode() + b"\0" + bytes.fromhex(oid)
        return object_hash("tree", data)

    return digest(tree)


def validate_manifest(value):
    if value.get("schema_version") != 1 or not re.fullmatch(
        "[0-9a-f]{40}", value.get("commit", "")
    ):
        raise ValueError("Unsupported source manifest")
    commit_data = value["commit_object"].encode()
    if object_hash("commit", commit_data) != value["commit"]:
        raise ValueError("Commit provenance mismatch")
    entries = value["git_tree"]
    if entries != sorted(entries, key=lambda e: e["path"]):
        raise ValueError("Unsorted Git tree")
    tree = tree_hash(entries)
    if not commit_data.startswith(f"tree {tree}\n".encode()):
        raise ValueError("Git tree provenance mismatch")
    for entry in entries:
        if not allowed(entry["path"]) and entry["path"] not in EXCLUDED:
            raise ValueError(f"Prohibited tracked artifact: {entry['path']}")
    expected = {e["path"]: e for e in entries if allowed(e["path"])}
    files = value["files"]
    if [e["path"] for e in files] != sorted(expected):
        raise ValueError("Missing, duplicate or prohibited source files")
    for entry in files:
        origin = expected[entry["path"]]
        if (
            entry["mode"] != origin["mode"]
            or entry["oid"] != origin["oid"]
            or not re.fullmatch("[0-9a-f]{64}", entry["sha256"])
            or not isinstance(entry["bytes"], int)
            or entry["bytes"] < 0
        ):
            raise ValueError("Invalid source file identity")
    return files


def verify_bytes(entry, data):
    if (
        len(data) != entry["bytes"]
        or hashlib.sha256(data).hexdigest() != entry["sha256"]
        or object_hash("blob", data) != entry["oid"]
    ):
        raise ValueError(f"Source content mismatch: {entry['path']}")


def manifest(root):
    path = regular(root, MANIFEST)
    value = json.loads(path.read_text())
    validate_manifest(value)
    return value


def names(root=ROOT):
    if checkout(root):
        return sorted(
            set(
                filter(
                    None,
                    git(root, "ls-files", "-z", "--cached", "--others", "--exclude-standard")
                    .decode()
                    .split("\0"),
                )
            )
        )
    return [entry["path"] for entry in manifest(root)["files"]]


def verify_directory(root):
    value = manifest(root)
    for entry in value["files"]:
        path = regular(root, entry["path"])
        verify_bytes(entry, path.read_bytes())
        if stat.S_IMODE(path.stat().st_mode) != int(entry["mode"][-3:], 8):
            raise ValueError(f"Source permission mismatch: {entry['path']}")
    expected = {e["path"] for e in value["files"]}
    for parent, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = [
            d for d in dirs if d not in FORBIDDEN and PurePosixPath(d).suffix not in SUFFIXES
        ]
        for name in dirs + files:
            relative = (Path(parent) / name).relative_to(root).as_posix()
            if allowed(relative) and (Path(parent) / name).is_symlink():
                raise ValueError(f"Unexpected source symlink: {relative}")
        for name in files:
            relative = (Path(parent) / name).relative_to(root).as_posix()
            if allowed(relative) and relative not in expected:
                raise ValueError(f"Unexpected source file: {relative}")
    return value


def identity(root=ROOT):
    if checkout(root):
        return {
            "commit": git(root, "rev-parse", "HEAD").decode().strip(),
            "dirty": bool(git(root, "status", "--porcelain")),
            "kind": "git",
        }
    value = verify_directory(root)
    return {"commit": value["commit"], "dirty": False, "kind": "source-archive"}
