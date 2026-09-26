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
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
POLICY = "config/storage/retention.json"
GIB = 1024**3
RUST_COMPILER_ROOT = ".local/builds/rust/debug/deps"
RUST_SELECTOR = "rust-debug-deps-compiler-v1"
BINARY_INSPECTION_TIMEOUT = 30


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
        selector = entry.get("selector")
        if selector not in {None, RUST_SELECTOR} or (
            selector == RUST_SELECTOR and name != RUST_COMPILER_ROOT
        ):
            raise ValueError("Unknown or misplaced cleanup selector")
        # Scope cannot be expanded by a plan, even when its checksum is recomputed.
        if not name.startswith((".local/builds/", "apps/ios/build/", "target/")) or not (
            (name == RUST_COMPILER_ROOT and selector == RUST_SELECTOR)
            or name.endswith(("/Intermediates.noindex", "/ModuleCache.noindex", "/Index.noindex"))
            or name in {"target/debug/incremental", ".local/builds/rust/debug/incremental"}
            or (name.startswith(".local/builds/probes/") and name.endswith("/modules"))
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
    selectors = {entry["path"]: entry.get("selector") for entry in candidates(root)["rebuildable"]}
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
            if selectors.get(name) == RUST_SELECTOR:
                dirs[:] = []  # The compiler selector never descends into a child directory.
            for child in sorted(leaves):
                path = Path(directory) / child
                relative = str(path.relative_to(root))
                if selectors.get(name) == RUST_SELECTOR:
                    if path.suffix not in {".rlib", ".rmeta", ".o"}:
                        continue
                    info = path.lstat()
                    if (
                        path.suffix in {".o", ".rmeta"}
                        and stat.S_ISREG(info.st_mode)
                        and info.st_size == 0
                    ):
                        continue  # Unknown empty placeholders remain protected, never selected.
                    compiler_file(root, relative)
                files[relative] = fingerprint(local_path(root, relative))
    return files


def retained_empty_objects(root, policy):
    if not any(e.get("selector") == RUST_SELECTOR for e in policy["rebuildable"]):
        return {}
    base = local_path(root, RUST_COMPILER_ROOT)
    if not base.exists():
        return {}
    result = {}
    for path in sorted(base.iterdir()):
        info = path.lstat()
        if path.suffix in {".o", ".rmeta"} and stat.S_ISREG(info.st_mode) and info.st_size == 0:
            result[str(path.relative_to(root))] = fingerprint(path)
    return result


def protected_inventory(root, policy, excluded=()):
    """Hash protected bytes without traversing symbolic links or external originals."""
    result = {}
    # A candidate directory may contain retained symbols, DLLs and diagnostics.
    # Only exact validated deletion names are excluded, never an entire subtree.
    protected = [*policy["protected"], *(e["path"] for e in policy["rebuildable"])]
    for name in dict.fromkeys(protected):
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
                if relative in excluded:
                    continue
                if path.is_symlink():
                    result[relative] = {"symlink": os.readlink(path)}
                elif path.is_file():
                    value = fingerprint(path)
                    result[relative] = {k: value[k] for k in ("bytes", "mode", "sha256")}
    digest = hashlib.sha256(json.dumps(result, sort_keys=True).encode()).hexdigest()
    return {"files": len(result), "sha256": digest}


def command(root, *args):
    return subprocess.check_output(args, cwd=root, text=True, stderr=subprocess.PIPE)


def compiler_file(root, name):
    """Accept only supported compiler formats with retained Cargo dep-info."""
    path = local_path(root, name)
    if path.parent != root / RUST_COMPILER_ROOT or not stat.S_ISREG(path.lstat().st_mode):
        raise ValueError("Compiler selection must be an immediate regular deps file")
    with path.open("rb") as stream:
        header = stream.read(20)
    suffix = path.suffix
    object_file = (
        len(header) >= 16
        and header[:4] == b"\xcf\xfa\xed\xfe"
        and int.from_bytes(header[12:16], "little") == 1
    )
    if not (
        (suffix == ".rlib" and header.startswith(b"!<arch>\n"))
        or (suffix == ".rmeta" and header.startswith(b"rust"))
        or (suffix == ".o" and object_file)
    ):
        raise ValueError(f"Not a supported compiler artifact: {name}")
    stem = (path.name.removeprefix("lib") if suffix != ".o" else path.name).split(".")[0]
    depinfo = local_path(root, str((path.parent / (stem + ".d")).relative_to(root)))
    if not depinfo.is_file():
        raise ValueError(f"Compiler artifact has no retained dep-info: {name}")


def generation_locations(root):
    """Resolve old absolute debug-map locations through completed rotation receipts."""
    base = local_path(root, ".local/builds/ios")
    if (base / "product-generation-pending.json").exists():
        raise ValueError("Pending product generation; preserve its recovery inputs")
    collection = local_path(root, ".local/builds/ios/generations")
    locations = []
    if collection.exists():
        for directory in sorted(collection.iterdir()):
            local_path(root, str(directory.relative_to(root)))
            if not directory.is_dir():
                raise ValueError("Unexpected product-generation entry")
            plan = local_path(root, str((directory / "plan.json").relative_to(root)))
            receipt = local_path(root, str((directory / "receipt.json").relative_to(root)))
            value = json.loads(receipt.read_text())
            planned = json.loads(plan.read_text())
            expected = str((directory / "DerivedData").relative_to(root))
            if (
                value.get("schema_version") != 1
                or planned.get("schema_version") != 1
                or planned.get("root") != str(root)
                or value.get("new_identity") != planned.get("identity", {}).get("sha256")
                or value.get("plan_sha256") != sha(plan)
                or value.get("previous_location") != ".local/builds/ios/DerivedData"
                or value.get("preserved_location") != expected
            ):
                raise ValueError("Invalid completed product-generation linkage")
            locations.append(local_path(root, expected))
    return locations


def compiler_family(name):
    """Identify a Cargo output group by its exact immediate deps crate/hash stem."""
    path = Path(name)
    if path.parent != Path(RUST_COMPILER_ROOT):
        return None
    if path.suffix in {".rlib", ".rmeta", ".a", ".dylib", ".so"}:
        stem = path.name.removeprefix("lib").split(".")[0]
    elif path.suffix == ".o" or not path.suffix:
        stem = path.name.split(".")[0]
    else:
        return None
    return stem if re.fullmatch(r".+-[0-9a-f]+", stem) else None


def binary_consumers(root):
    """Inspect retained Mach-O files, including non-executable images and dSYMs."""
    if sys.platform != "darwin":
        raise ValueError("Cleanup consumer inspection supports Darwin/Mach-O only")
    generations = generation_locations(root)
    policy = candidates(root)
    binaries = {}
    available = set()
    compiler_objects = set()
    family_members = {}
    retained_families = {}
    by_basename = {}

    def unreadable(error):
        raise ValueError("Cannot inventory every local binary consumer") from error

    for directory, dirs, leaves in os.walk(root, followlinks=False, onerror=unreadable):
        dirs[:] = sorted(n for n in dirs if n != ".git")
        for name in sorted(leaves):
            path = Path(directory) / name
            info = path.lstat()
            if stat.S_ISREG(info.st_mode):
                by_basename.setdefault(name, []).append(str(path.relative_to(root)))
            elif stat.S_ISLNK(info.st_mode):
                resolved = path.resolve()
                if resolved.is_relative_to(root):
                    by_basename.setdefault(name, []).append(str(resolved.relative_to(root)))
            if not stat.S_ISREG(info.st_mode):
                continue
            relative = str(path.relative_to(root))
            family = compiler_family(relative)
            if family and path.suffix in {".rlib", ".rmeta", ".o"}:
                family_members.setdefault(family, set()).add(relative)
            with path.open("rb") as stream:
                header = stream.read(16)
            # Unsupported external-reference formats must not look like no consumers.
            # Ordinary !<arch> archives embed their members; thin archives do not.
            if header.startswith(b"!<thin>\n"):
                raise ValueError(f"Unsupported retained thin archive: {path.relative_to(root)}")
            if header.startswith(
                (b"\x7fELF", b"BC\xc0\xde", b"\xde\xc0\x17\x0b")
            ) or path.name.endswith((".dwo", ".dwp", ".thinlto.bc", ".imports")):
                raise ValueError(
                    f"Unsupported retained ELF/LLVM or debug/LTO sidecar: {path.relative_to(root)}"
                )
            magic = header[:4]
            if magic not in {
                b"\xcf\xfa\xed\xfe",
                b"\xfe\xed\xfa\xcf",
                b"\xce\xfa\xed\xfe",
                b"\xfe\xed\xfa\xce",
                b"\xca\xfe\xba\xbe",
                b"\xbe\xba\xfe\xca",
                b"\xca\xfe\xba\xbf",
                b"\xbf\xba\xfe\xca",
            }:
                continue
            relative = str(path.relative_to(root))
            available.add(relative)
            # Only unreferenced owned compiler objects may disappear. All other
            # Mach-O products (including 0644 images/dSYMs) are retained roots.
            byteorder = "little" if magic in {b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe"} else "big"
            thin = magic in {
                b"\xcf\xfa\xed\xfe",
                b"\xce\xfa\xed\xfe",
                b"\xfe\xed\xfa\xcf",
                b"\xfe\xed\xfa\xce",
            }
            if (
                thin
                and len(header) == 16
                and int.from_bytes(header[12:16], byteorder) == 1
                and authorized_file(relative, policy)
            ):
                compiler_objects.add(relative)
    references = available - compiler_objects

    def retain_families():
        # Cargo can rewrite a kept OSO input when a sibling output is missing.
        # Preserve the complete exact crate/hash group, including metadata.
        for ref in tuple(references):
            family = compiler_family(ref)
            if family in family_members and family not in retained_families:
                retained_families[family] = sorted(family_members[family])
                references.update(family_members[family])

    def reference(raw):
        # Archive members have their own symbols but consume the enclosing archive.
        raw = re.split(r"(?<=\.rlib)\(|(?<=\.a)\(", raw, maxsplit=1)[0]
        path = Path(raw)
        if raw.startswith("@") or not path.is_absolute():
            # Rpath/loader expansion can be ambiguous: retain every local match.
            references.update(by_basename.get(path.name, []))
            if raw.startswith("@"):
                return
            path = root / path
        path = path.resolve()
        if path.is_relative_to(root):
            references.add(str(path.relative_to(root)))
        current = root / ".local/builds/ios/DerivedData"
        if path.is_relative_to(current):
            relative = path.relative_to(current)
            for preserved in generations:
                references.add(str((preserved / relative).relative_to(root)))

    descendants = {}
    for name in available:
        for parent in Path(name).parents:
            descendants.setdefault(str(parent), set()).add(name)
    followed = set()
    retain_families()
    pending = sorted(references & available)
    while pending:
        names, pending = pending[:32], pending[32:]
        for name in names:
            binaries[name] = fingerprint(root / name)
        batch = [str(root / n) for n in names]
        for tool, args in (("nm", ["-ap"]), ("otool", ["-L"])):
            try:
                result = subprocess.run(
                    [tool, *args, *batch],
                    text=True,
                    capture_output=True,
                    timeout=BINARY_INSPECTION_TIMEOUT,
                )
            except subprocess.TimeoutExpired as error:
                raise ValueError(
                    f"Retained binary consumer inspection timed out: {tool}"
                ) from error
            except OSError as error:
                raise ValueError(f"Cannot start retained binary inspection: {tool}") from error
            diagnostics = [s for s in result.stderr.splitlines() if s.strip()]
            if result.returncode or any(not s.endswith(": no symbols") for s in diagnostics):
                raise ValueError(f"Cannot inspect retained binary consumers with {tool}")
            for line in result.stdout.splitlines():
                if tool == "nm":
                    match = re.search(r"\b(?:OSO|AST) (.+)$", line)
                    if match:
                        reference(match.group(1))
                elif line.startswith("\t"):
                    reference(line.strip().split(" (compatibility version", 1)[0])
        # A retained image can consume a candidate object which itself carries
        # a debug map. Follow that chain instead of treating it as disposable.
        retain_families()
        added = set()
        for ref in references - followed:
            added.update({ref} if ref in available else descendants.get(ref, ()))
        followed.update(references)
        added.difference_update(binaries)
        references.update(added)
        pending = sorted(set(pending) | added)
    # A byte change during symbol inspection must not produce a mixed snapshot.
    if any(fingerprint(root / n) != value for n, value in binaries.items()):
        raise ValueError("Retained binary changed during consumer inspection")
    return {
        "files": binaries,
        "references": sorted(references),
        "compiler_families": retained_families,
    }


def eligible(root, names, consumers):
    references = [Path(name) for name in consumers["references"]]
    return {
        name: value
        for name, value in inventory(root, names).items()
        if not any(Path(name).is_relative_to(reference) for reference in references)
    }


def authorized_file(name, policy):
    if Path(name).is_absolute() or ".." in Path(name).parts:
        return False
    for entry in policy["rebuildable"]:
        if not Path(name).is_relative_to(entry["path"]):
            continue
        if entry.get("selector") == RUST_SELECTOR:
            return Path(name).parent == Path(RUST_COMPILER_ROOT) and Path(name).suffix in {
                ".rlib",
                ".rmeta",
                ".o",
            }
        return True
    return False


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
    consumers = binary_consumers(root)
    files = eligible(root, names, consumers)
    value = {
        "schema_version": 2,
        "root": str(root),
        "policy_sha256": sha(root / POLICY),
        "source_revision": command(root, "git", "rev-parse", "HEAD").strip(),
        "free_bytes": shutil.disk_usage(root).free,
        "candidates": policy["rebuildable"],
        "protected": policy["protected"],
        "protected_inventory": protected_inventory(root, policy, files),
        "binary_consumers": consumers,
        "retained_empty_objects": retained_empty_objects(root, policy),
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
        value["schema_version"] != 2
        or value["root"] != str(root)
        or value["policy_sha256"] != sha(root / POLICY)
        or value["candidates"] != policy["rebuildable"]
        or any(not authorized_file(n, policy) for n in value["files"])
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
    consumers = binary_consumers(root)
    if consumers != value["binary_consumers"]:
        raise ValueError("Retained binary consumers changed after the preview")
    if retained_empty_objects(root, policy) != value.get("retained_empty_objects", {}):
        raise ValueError("Retained empty object placeholders changed after the preview")
    if any(
        Path(name).is_relative_to(reference)
        for name in value["files"]
        for reference in consumers["references"]
    ):
        raise ValueError("Plan selects retained runtime/debug-map inputs")
    if protected_inventory(root, policy, value["files"]) != value["protected_inventory"]:
        raise ValueError("Protected files changed after the preview")
    current = eligible(root, names, consumers)
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
    remaining = eligible(root, names, consumers)
    if remaining:
        raise ValueError("Candidate was repopulated during cleanup; inspect before resuming")
    if binary_consumers(root) != consumers:
        raise ValueError("Retained binary consumers changed during cleanup")
    protected = protected_inventory(root, policy, value["files"])
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
