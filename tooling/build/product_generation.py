"""Lease shared native inputs and preserve Xcode products across contract changes."""

import argparse
import fcntl
import hashlib
import json
import os
import stat
import subprocess
import sys
import uuid
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tooling/dev"))
import source_tree  # noqa: E402
import workspace  # noqa: E402

import artifacts  # noqa: E402

INPUTS = (
    "apps/ios/project.yml",
    "ml/registry/runtime/small.lock.json",
    "ml/registry/runtime/ios-runtime.lock.json",
    "docs/third-party/licenses/manifest.json",
    "docs/third-party/runtime-inventory.json",
    "tooling/release/runtime_policy.py",
    "tooling/build/build-native.sh",
    "tooling/build/product_generation.py",
    "config/toolchains/versions.json",
)
MARKER = ".reha-product-generation.json"
LEASE_DESCRIPTOR = "REHA_NATIVE_BUILD_LEASE_FD"


def sync_directory(path):
    handle = os.open(path, os.O_RDONLY)
    try:
        os.fsync(handle)
    finally:
        os.close(handle)


def publish(path, value):
    artifacts.write_new(path, value)
    sync_directory(path.parent)


def identity(root):
    sources = {name: artifacts.sha(artifacts.local_path(root, name)) for name in INPUTS}
    value = {"schema_version": 1, "sources": sources}
    value["sha256"] = hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()
    return value


def location(root):
    base = workspace.location("ios", root)
    artifacts.local_path(root, str(base.relative_to(root)))
    return base


def inventory(path):
    """Hash owned bytes; preserve symbolic links verbatim without following them."""
    result = {}
    if not path.exists():
        return result
    if not path.is_dir() or path.is_symlink():
        raise ValueError("DerivedData must be an independently owned directory")
    for parent, folders, files in os.walk(path, followlinks=False):
        for name in sorted(folders + files):
            item = Path(parent) / name
            relative = str(item.relative_to(path))
            info = item.lstat()
            if stat.S_ISLNK(info.st_mode):
                result[relative] = {"type": "symlink", "target": os.readlink(item)}
            elif stat.S_ISDIR(info.st_mode):
                result[relative] = {"type": "directory", "mode": stat.S_IMODE(info.st_mode)}
            elif stat.S_ISREG(info.st_mode):
                result[relative] = {"type": "file", **artifacts.fingerprint(item)}
            else:
                raise ValueError("Unexpected socket/device in DerivedData; preserve for review")
    return result


def ensure_quiet(root, current):
    output = subprocess.check_output(["ps", "-axo", "pid=,ppid=,comm="], text=True)
    processes = {}
    for line in output.splitlines():
        pid, parent, command = line.strip().split(None, 2)
        processes[int(pid)] = (int(parent), command)
    ancestors, cursor = set(), os.getpid()
    while cursor and cursor not in ancestors:
        ancestors.add(cursor)
        cursor = processes.get(cursor, (0, ""))[0]
    for pid, (_, command) in processes.items():
        executable = Path(command).name
        if pid not in ancestors and executable in {
            "xcodebuild",
            "cargo",
            "rustc",
            "swiftc",
            "swift-frontend",
            "make",
            "gmake",
        }:
            raise ValueError(f"Active build process {pid}; leave existing products in place")
    if source_tree.checkout(root):
        worktrees = subprocess.check_output(
            ["git", "worktree", "list", "--porcelain"], cwd=root, text=True
        )
    else:
        source_tree.identity(root)
        worktrees = ""
    for line in worktrees.splitlines():
        if line.startswith("worktree ") and Path(line[9:]).resolve().is_relative_to(
            current.resolve()
        ):
            raise ValueError("A worktree uses the existing product directory")
    if current.exists():
        opened = subprocess.run(
            ["lsof", "-nP", "+D", str(current), "-F", "pn"], text=True, capture_output=True
        )
        if opened.returncode not in {0, 1} or opened.stdout.strip() or opened.stderr.strip():
            raise ValueError("Existing product directory has open files or cannot be checked")


@contextmanager
def leased(root, *, inherit=True):
    """Protect shared native inputs and products, including delegated shell builds."""
    base = location(root)
    base.mkdir(parents=True, exist_ok=True)
    lock = artifacts.local_path(root, str((base / "product-generation.lock").relative_to(root)))
    inherited = os.environ.get(LEASE_DESCRIPTOR) if inherit else None
    if inherited is not None:
        try:
            descriptor = int(inherited)
            actual, expected = os.fstat(descriptor), lock.stat()
            if (actual.st_dev, actual.st_ino) != (expected.st_dev, expected.st_ino):
                raise ValueError("Native build lease descriptor belongs to a different file")
            # An environment flag alone is insufficient. The inherited open-file
            # description must own (or acquire) this exact exclusive lock.
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except (OSError, ValueError) as error:
            raise ValueError("Invalid inherited native build lease") from error
        yield base, descriptor
        return
    with lock.open("a+") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield base, stream.fileno()


@contextmanager
def locked(root):
    """Acquire an independent lease; callers cannot bypass an existing consumer."""
    with leased(root, inherit=False) as (base, _):
        yield base


def delegate(root, command, descriptor):
    """Only cooperating entry points inherit the lock; ordinary tools do not."""
    env = dict(os.environ, **{LEASE_DESCRIPTOR: str(descriptor)})
    return subprocess.run(command, cwd=root, env=env, pass_fds=(descriptor,), check=False)


def checked_marker(root):
    base = location(root)
    current = artifacts.local_path(root, str((base / "DerivedData").relative_to(root)))
    pointer = base / "product-generation-pending.json"
    if pointer.exists():
        raise ValueError("Interrupted product rotation; rerun make build before consuming products")
    marker = artifacts.local_path(root, str((current / MARKER).relative_to(root)))
    expected = identity(root)
    if not marker.is_file() or json.loads(marker.read_text()).get("identity") != expected:
        raise ValueError("Stale/unknown product generation; run make build before --built checks")
    return current


def prepare(root, base):
    """Caller holds the product lease, including any subsequent xcodebuild process."""
    current = artifacts.local_path(root, str((base / "DerivedData").relative_to(root)))
    pending = artifacts.local_path(
        root, str((base / "product-generation-pending.json").relative_to(root))
    )
    expected = identity(root)
    marker = artifacts.local_path(root, str((current / MARKER).relative_to(root)))
    if (
        not pending.exists()
        and marker.is_file()
        and json.loads(marker.read_text()).get("identity") == expected
    ):
        return current
    ensure_quiet(root, current)
    with artifacts.locked(root):
        if pending.exists():
            transition = json.loads(pending.read_text())
            directory = artifacts.local_path(root, transition["directory"])
            if directory.parent != base / "generations":
                raise ValueError("Product generation escaped its protected collection")
            plan_path = artifacts.local_path(root, str((directory / "plan.json").relative_to(root)))
            if artifacts.sha(plan_path) != transition["plan_sha256"]:
                raise ValueError("Product rotation plan changed")
            plan = json.loads(plan_path.read_text())
            if plan["identity"] != expected or plan["root"] != str(root):
                raise ValueError("Sources changed during interrupted product rotation")
        else:
            directory = base / "generations" / uuid.uuid4().hex
            artifacts.local_path(root, str(directory.relative_to(root)))
            directory.mkdir(parents=True, mode=0o700)
            sync_directory(directory.parent)
            sync_directory(base)
            plan = {
                "schema_version": 1,
                "root": str(root),
                "identity": expected,
                "previous_directory_existed": current.exists(),
                "previous_files": inventory(current),
            }
            plan_path = artifacts.local_path(root, str((directory / "plan.json").relative_to(root)))
            publish(plan_path, plan)
            publish(
                pending,
                {
                    "directory": str(directory.relative_to(root)),
                    "plan_sha256": artifacts.sha(plan_path),
                },
            )
        previous = artifacts.local_path(root, str((directory / "DerivedData").relative_to(root)))
        receipt = artifacts.local_path(root, str((directory / "receipt.json").relative_to(root)))
        if identity(root) != expected:
            raise ValueError("Build contract changed while preparing the generation")
        new_marker = {"identity": expected, "transition": str(directory.relative_to(root))}
        if plan["previous_directory_existed"]:
            if not previous.exists():
                if inventory(current) != plan["previous_files"]:
                    raise ValueError("Previous build contents changed before rotation")
                current.rename(
                    previous
                )  # Same-volume rename; no cache, product or evidence is deleted.
                sync_directory(base)
                sync_directory(directory)
            if inventory(previous) != plan["previous_files"]:
                raise ValueError("Preserved generation differs from the rotation inventory")
        if not current.exists():
            current.mkdir(mode=0o700)
            sync_directory(base)
        children = set(p.name for p in current.iterdir())
        if not children:
            publish(marker, new_marker)
        elif children != {MARKER} or json.loads(marker.read_text()) != new_marker:
            raise ValueError("Unexpected new files during interrupted product rotation")
        if not receipt.exists():
            publish(
                receipt,
                {
                    "schema_version": 1,
                    "plan_sha256": artifacts.sha(plan_path),
                    "previous_location": str(current.relative_to(root)),
                    "preserved_location": str(previous.relative_to(root))
                    if previous.exists()
                    else None,
                    "new_identity": expected["sha256"],
                    "files_deleted": 0,
                    "historical_reports_modified": False,
                    "recovery": "Prior files and raw symlink targets are preserved. Absolute links into the former DerivedData path may require restoring that generation to its recorded original location before use.",
                },
            )
        elif json.loads(receipt.read_text()).get("plan_sha256") != artifacts.sha(plan_path):
            raise ValueError("Product rotation receipt changed")
        pending.unlink()
        sync_directory(base)
    return current


def build(root, command):
    if not command or Path(command[0]).name != "xcodebuild" or "-derivedDataPath" in command:
        raise ValueError("Pass xcodebuild arguments without an independent DerivedData override")
    with leased(root) as (base, _):
        current = prepare(root, base)
        env = {key: value for key, value in os.environ.items() if key != LEASE_DESCRIPTOR}
        result = subprocess.run(
            [*command, "-derivedDataPath", str(current)], cwd=root, env=env, check=False
        )
        checked_marker(root)
        return result.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["build", "check", "lease", "check-lease"])
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.action == "check":
        print(checked_marker(ROOT))
    elif args.action == "check-lease":
        if LEASE_DESCRIPTOR not in os.environ:
            raise ValueError("Native build entry requires an inherited lease")
        with leased(ROOT):
            pass
    else:
        command = args.command[1:] if args.command[:1] == ["--"] else args.command
        if args.action == "lease":
            if not command:
                parser.error("lease requires a command")
            with leased(ROOT) as (_, descriptor):
                raise SystemExit(delegate(ROOT, command, descriptor).returncode)
        else:
            raise SystemExit(build(ROOT, command))


if __name__ == "__main__":
    main()
