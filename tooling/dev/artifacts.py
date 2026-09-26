"""Prune reviewed, reproducible intermediates with immutable plans and restart receipts.

Only versioned policy roots may be removed. Models, runs, datasets, archives and
external directories are deliberately outside this first policy. No age heuristic
can turn evidence into a disposable cache.
"""

import argparse
import fcntl
import hashlib
import json
import math
import os
import shutil
import stat
import subprocess
import tempfile
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
POLICY = "config/storage/retention.json"
GIB = 1024**3


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_new(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent) as stream:
        json.dump(value, stream, indent=2, ensure_ascii=False)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
        os.link(stream.name, path)  # Atomic publication, never overwrite an earlier receipt.


def local_path(root, name):
    relative = Path(name)
    if relative.is_absolute() or ".." in relative.parts or str(relative) in {"", "."}:
        raise ValueError(f"Not a project-relative path: {name}")
    path = root / relative
    # Never follow a replaced directory to an original, backup or another checkout.
    for part in [path, *path.parents]:
        if part == root:
            break
        if part.is_symlink():
            raise ValueError(f"Symbolic link in managed path: {name}")
    if not path.resolve().is_relative_to(root.resolve()):
        raise ValueError(f"Path escapes checkout: {name}")
    return path


def candidates(root):
    policy = json.loads((root / POLICY).read_text())
    names = [entry["path"] for entry in policy["rebuildable"]]
    for entry in policy["rebuildable"]:
        name = entry["path"]
        # Scope cannot be expanded by a plan, even when its checksum is recomputed.
        if not name.startswith((".local/builds/", "apps/ios/build/", "target/")) or not (
            name.endswith(("/Intermediates.noindex", "/ModuleCache.noindex", "/Index.noindex"))
            or name == "target/debug/incremental"
        ):
            raise ValueError(f"Not an approved intermediate class: {name}")
        local_path(root, name)
        if not entry["reason"] or not entry["rebuild"] or not entry["consumers"]:
            raise ValueError("Every candidate needs consumer and recovery evidence")
    if len(names) != len(set(names)) or any(
        Path(a).is_relative_to(b) for a in names for b in names if a != b
    ):
        raise ValueError("Overlapping candidate roots")
    return policy


def fingerprint(path):
    before = path.lstat()
    if stat.S_ISLNK(before.st_mode) or not stat.S_ISREG(before.st_mode):
        raise ValueError(f"Not a regular intermediate: {path}")
    result = {
        "bytes": before.st_size,
        "allocated_bytes": before.st_blocks * 512,
        "mode": stat.S_IMODE(before.st_mode),
        "mtime_ns": before.st_mtime_ns,
        "device": before.st_dev,
        "inode": before.st_ino,
        "sha256": sha(path),
    }
    after = path.lstat()
    if any(
        getattr(before, key) != getattr(after, key)
        for key in ("st_size", "st_mtime_ns", "st_ctime_ns", "st_mode", "st_ino", "st_dev")
    ):
        raise ValueError(f"File changed during inventory: {path}")
    return result


def inventory(root, names):
    files = {}
    for name in names:
        base = local_path(root, name)
        if not base.exists():
            continue
        if not base.is_dir():
            raise ValueError(f"Expected a generated directory: {name}")
        for directory, dirs, leaves in os.walk(base, followlinks=False):
            for child in dirs:
                local_path(root, str((Path(directory) / child).relative_to(root)))
            for child in sorted(leaves):
                path = Path(directory) / child
                relative = str(path.relative_to(root))
                files[relative] = fingerprint(local_path(root, relative))
    return files


def protected_inventory(root, policy):
    """Hash protected bytes without traversing symbolic links or external originals."""
    result = {}
    for name in policy["protected"]:
        if name == "external originals and simulators":
            continue
        base = local_path(root, name)
        if not base.exists():
            continue
        for directory, dirs, leaves in os.walk(base, followlinks=False):
            dirs[:] = sorted(dirs)
            for child in sorted(dirs + leaves):
                path = Path(directory) / child
                relative = str(path.relative_to(root))
                if path.is_symlink():
                    result[relative] = {"symlink": os.readlink(path)}
                elif path.is_file():
                    value = fingerprint(path)
                    result[relative] = {k: value[k] for k in ("bytes", "mode", "sha256")}
    digest = hashlib.sha256(json.dumps(result, sort_keys=True).encode()).hexdigest()
    return {"files": len(result), "sha256": digest}


def command(root, *args):
    return subprocess.check_output(args, cwd=root, text=True, stderr=subprocess.PIPE)


def guard(root, names):
    """Conservatively refuse active builders, nested worktrees and open cache files."""
    roots = [root / n for n in names]
    processes = command(root, "ps", "-axo", "pid=,comm=")
    busy = {"cargo", "rustc", "swift", "swiftc", "xcodebuild", "uv", "cmake", "ninja", "make"}
    ancestors = {os.getpid(), os.getppid()}
    for line in processes.splitlines():
        pid, _, executable = line.strip().partition(" ")
        # Make may invoke this tool directly; only that immediate parent is exempt.
        if int(pid) not in ancestors and Path(executable.strip()).name in busy:
            raise ValueError(f"Active build/tool process {pid}; retry after it exits")
    for line in command(root, "git", "worktree", "list", "--porcelain").splitlines():
        if line.startswith("worktree "):
            worktree = Path(line.removeprefix("worktree "))
            if any(worktree.is_relative_to(p) for p in roots):
                raise ValueError("Candidate contains a registered worktree")
    # lsof returns 1 for an empty selection. Errors must not look like an empty list.
    result = subprocess.run(
        ["lsof", "-n", "-Fpn", "-u", str(os.getuid())],
        text=True,
        capture_output=True,
        cwd=root,
    )
    if result.returncode not in {0, 1} or result.stderr:
        raise ValueError("Cannot establish open-file safety with lsof")
    for line in result.stdout.splitlines():
        if line.startswith("n/"):
            path = Path(line[1:])
            if any(path.is_relative_to(p) for p in roots):
                raise ValueError("A process is using a candidate; retry after it exits")
    tracked = command(root, "git", "ls-files", "-z").split("\0")
    if any(Path(n).is_relative_to(p) for n in tracked if n for p in names):
        raise ValueError("Candidate contains versioned files")
    # A symlink consumer outside the deletion set is a live reference, not a cache hint.
    for directory, dirs, leaves in os.walk(root, followlinks=False):
        dirs[:] = [n for n in dirs if n != ".git"]
        for name in dirs + leaves:
            link = Path(directory) / name
            if link.is_symlink() and not any(link.is_relative_to(p) for p in roots):
                target = link.resolve()
                if any(target.is_relative_to(p) for p in roots):
                    raise ValueError(f"Live symbolic reference: {link.relative_to(root)}")


@contextmanager
def locked(root):
    path = local_path(root, ".local/maintenance/cleanup.lock")
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with path.open("a") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield


def plan(root, destination):
    policy = candidates(root)
    names = [entry["path"] for entry in policy["rebuildable"]]
    guard(root, names)
    files = inventory(root, names)
    value = {
        "schema_version": 1,
        "root": str(root),
        "policy_sha256": sha(root / POLICY),
        "source_revision": command(root, "git", "rev-parse", "HEAD").strip(),
        "free_bytes": shutil.disk_usage(root).free,
        "candidates": policy["rebuildable"],
        "protected": policy["protected"],
        "protected_inventory": protected_inventory(root, policy),
        "files": files,
        "logical_bytes": sum(v["bytes"] for v in files.values()),
        "allocated_bytes_upper_bound": sum(v["allocated_bytes"] for v in files.values()),
        "space_note": "Allocated blocks can share APFS extents; only volume delta is measured.",
    }
    write_new(destination, value)
    return value


def events(path):
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text().splitlines()]


def append(path, event):
    with open(path, "a", opener=lambda p, f: os.open(p, f, 0o600)) as stream:
        stream.write(json.dumps(event) + "\n")
        stream.flush()
        os.fsync(stream.fileno())


def apply(root, source):
    policy = candidates(root)
    value = json.loads(source.read_text())
    names = [entry["path"] for entry in policy["rebuildable"]]
    if (
        value["schema_version"] != 1
        or value["root"] != str(root)
        or value["policy_sha256"] != sha(root / POLICY)
        or value["candidates"] != policy["rebuildable"]
        or any(not any(Path(n).is_relative_to(p) for p in names) for n in value["files"])
    ):
        raise ValueError("Plan no longer matches the reviewed checkout policy")
    journal = source.with_suffix(".journal.jsonl")
    receipt = source.with_suffix(".receipt.json")
    local_path(root, str(journal.relative_to(root)))
    local_path(root, str(receipt.relative_to(root)))
    previous = events(journal)
    digest = sha(source)
    if previous and previous[0].get("plan_sha256") != digest:
        raise ValueError("Plan changed after cleanup started")
    if receipt.exists():
        result = json.loads(receipt.read_text())
        if result["plan_sha256"] != digest:
            raise ValueError("Receipt belongs to another plan")
        return result  # A completed replay must not delete a later rebuild.
    guard(root, names)
    if protected_inventory(root, policy) != value["protected_inventory"]:
        raise ValueError("Protected files changed after the preview")
    current = inventory(root, names)
    intended = {e["path"] for e in previous if e["action"] == "unlink-intent"}
    if set(current) - value["files"].keys():
        raise ValueError("New files appeared after the preview")
    for name, expected in value["files"].items():
        if name not in current:
            if name not in intended:
                raise ValueError(f"File disappeared without a cleanup intent: {name}")
        elif current[name] != expected:
            raise ValueError(f"File changed after the preview: {name}")
    if not previous:
        append(
            journal,
            {
                "action": "started",
                "plan_sha256": digest,
                "free_bytes": shutil.disk_usage(root).free,
            },
        )
        previous = events(journal)
    for name, expected in current.items():
        path = local_path(root, name)
        if fingerprint(path) != expected:
            raise ValueError(f"File changed before deletion: {name}")
        append(journal, {"action": "unlink-intent", "path": name})
        path.unlink()
    # Leave empty directories in place. Never recursively remove newly written files.
    remaining = inventory(root, names)
    if remaining:
        raise ValueError("Candidate was repopulated during cleanup; inspect before resuming")
    protected = protected_inventory(root, policy)
    if protected != value["protected_inventory"]:
        raise ValueError("Protected files changed during cleanup; retain journal for investigation")
    free = shutil.disk_usage(root).free
    result = {
        "schema_version": 1,
        "plan_sha256": digest,
        "status": "removed-rebuildable",
        "deleted_files": len(value["files"]),
        "logical_bytes": value["logical_bytes"],
        "free_before_bytes": previous[0]["free_bytes"],
        "free_after_bytes": free,
        "observed_volume_delta_bytes": free - previous[0]["free_bytes"],
        "reserve_met": free >= policy["reserve_gib"] * GIB,
        "protected": policy["protected"],
        "protected_inventory": protected,
        "limitation": "Volume delta also reflects concurrent system activity; no APFS estimate.",
    }
    write_new(receipt, result)
    return result


def space(root, peak_gib):
    reserve = json.loads((root / POLICY).read_text())["reserve_gib"]
    free = shutil.disk_usage(root).free / GIB
    if not math.isfinite(peak_gib) or peak_gib < 0 or free < reserve + peak_gib:
        raise ValueError(f"{free:.1f} GiB free; need {reserve} GiB reserve + {peak_gib:g} GiB peak")
    return {"free_gib": free, "reserve_gib": reserve, "peak_gib": peak_gib}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["plan", "apply", "space"])
    parser.add_argument("--manifest", default=".local/maintenance/cleanup.json")
    parser.add_argument("--peak-gib", type=float, default=0)
    args = parser.parse_args()
    root = ROOT.resolve()
    destination = local_path(root, args.manifest)
    if not destination.is_relative_to(root / ".local/maintenance"):
        raise ValueError("Cleanup evidence belongs below .local/maintenance")
    with locked(root):
        value = (
            space(root, args.peak_gib)
            if args.action == "space"
            else (plan(root, destination) if args.action == "plan" else apply(root, destination))
        )
    print(json.dumps({k: v for k, v in value.items() if k != "files"}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        raise SystemExit(str(error)) from error
