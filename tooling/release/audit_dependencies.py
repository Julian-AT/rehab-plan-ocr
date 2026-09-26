"""Pinned cargo-audit setup, explicit advisory refresh and offline review.

This optional macOS/ARM audit tool is independent of Homebrew after setup. It
never updates Cargo dependencies or turns a RustSec result into release approval.
"""

import argparse
import hashlib
import json
import os
import platform
import re
import subprocess
import sys
import tarfile
import tempfile
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "dev"))
import workspace  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
POLICY = "config/toolchains/cargo-audit.json"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def now():
    return datetime.now(timezone.utc).isoformat()


def policy(root):
    value = json.loads((root / POLICY).read_text())
    if value.get("schema_version") != 1:
        raise ValueError("Unsupported audit tool policy")
    return value


def host_supported(pin):
    if (
        platform.system() != "Darwin"
        or platform.machine() != "arm64"
        or int(platform.mac_ver()[0].split(".")[0]) < pin["minimum_macos"]
    ):
        raise ValueError("The reviewed cargo-audit bottle requires ARM64 macOS 26 or newer")


def local_path(root, path):
    path = Path(os.path.abspath(root / path))
    local = root / ".local"
    if not path.is_relative_to(local) or not path.resolve().is_relative_to(local):
        raise ValueError("Audit outputs must remain inside .local without escaping symlinks")
    if path.is_symlink():
        raise ValueError("Audit outputs must not be symbolic links")
    return path


def write_new(path, value):
    with path.open("x") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")


def default_archive(root, pin):
    return root / ".local/downloads" / f"cargo-audit-{pin['version']}-arm64_tahoe.tar.gz"


def check_archive(path, pin):
    if path.is_symlink() or not path.is_file():
        raise ValueError("A regular pinned cargo-audit bottle is required")
    if (
        path.stat().st_size != pin["archive"]["bytes"]
        or sha(path.read_bytes()) != pin["archive"]["sha256"]
    ):
        raise ValueError("cargo-audit bottle checksum or size mismatch")


def download(root):
    pin = policy(root)
    target = local_path(root, default_archive(root, pin))
    if target.exists():
        check_archive(target, pin)
        return target
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="cargo-audit-", dir=target.parent) as temp:
        candidate = Path(temp) / "bottle.tar.gz"
        subprocess.run(
            [
                "curl",
                "--fail",
                "--location",
                "--silent",
                "--show-error",
                "--max-time",
                "120",
                # Homebrew's public anonymous GHCR bearer; no user token is read.
                "--header",
                "Authorization: Bearer QQ==",
                "--output",
                str(candidate),
                pin["archive"]["url"],
            ],
            check=True,
        )
        check_archive(candidate, pin)
        # Never replace another process's completed download.
        os.link(candidate, target)
    return target


def tool(root, pin):
    binary = workspace.location("tools", root) / "bin/cargo-audit"
    local_path(root, binary)
    if (
        binary.is_symlink()
        or not binary.is_file()
        or sha(binary.read_bytes()) != pin["binary_sha256"]
    ):
        raise ValueError(
            "Pinned local cargo-audit is absent or changed; run setup-dependency-audit"
        )
    return binary


def setup(root, archive=None):
    pin = policy(root)
    host_supported(pin)
    archive = archive or default_archive(root, pin)
    check_archive(archive, pin)
    with tarfile.open(archive) as bottle:
        matches = [m for m in bottle if m.name == pin["archive"]["binary_member"]]
        if len(matches) != 1 or not matches[0].isfile() or matches[0].size != pin["binary_bytes"]:
            raise ValueError("Unexpected cargo-audit bottle member")
        data = bottle.extractfile(matches[0]).read()
    if sha(data) != pin["binary_sha256"]:
        raise ValueError("cargo-audit executable checksum mismatch")
    binary = workspace.location("tools", root) / "bin/cargo-audit"
    local_path(root, binary)
    binary.parent.mkdir(parents=True, exist_ok=True)
    if binary.exists() or binary.is_symlink():
        tool(root, pin)
    else:
        with tempfile.NamedTemporaryFile(dir=binary.parent, prefix=".audit-") as temporary:
            temporary.write(data)
            temporary.flush()
            os.chmod(temporary.name, 0o755)
            os.link(temporary.name, binary)
    version = subprocess.check_output([str(binary), "--version"], text=True).strip()
    if version != f"cargo-audit {pin['version']}":
        raise ValueError("Pinned executable reports an unexpected version")
    return {
        "version": version,
        "binary_sha256": sha(binary.read_bytes()),
        "archive_sha256": pin["archive"]["sha256"],
        "binary": str(binary.relative_to(root)),
    }


def git(db, *args):
    return subprocess.check_output(
        ["git", "-c", "core.fsmonitor=false", "-C", str(db), *args], stderr=subprocess.PIPE
    )


def database_identity(db, expected, pin):
    if not re.fullmatch(r"[a-f0-9]{40}", expected or "") or db.is_symlink():
        raise ValueError("An explicit RustSec commit and regular database directory are required")
    if git(db, "rev-parse", "HEAD").decode().strip() != expected:
        raise ValueError("Advisory database commit differs from the requested snapshot")
    if git(db, "remote", "get-url", "origin").decode().strip() != pin["database_url"]:
        raise ValueError("Advisory database origin differs from RustSec")
    if git(db, "status", "--porcelain", "--untracked-files=all"):
        raise ValueError("Advisory database has local changes")
    # Rehash tracked bytes as well: assume-unchanged/skip-worktree flags must not
    # let Git status hide modified advisory content.
    files = {}
    for entry in git(db, "ls-tree", "-r", "-z", "HEAD").split(b"\0"):
        if not entry:
            continue
        metadata, name = entry.split(b"\t", 1)
        mode, kind, blob = metadata.split()
        relative = name.decode()
        path = db / relative
        if (
            mode not in {b"100644", b"100755"}
            or kind != b"blob"
            or path.is_symlink()
            or not path.resolve().is_relative_to(db.resolve())
            or not path.is_file()
        ):
            raise ValueError("Unexpected advisory database file")
        data = path.read_bytes()
        actual = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        if actual != blob.decode():
            raise ValueError("Advisory bytes differ from the requested Git commit")
        files[relative] = sha(data)
    if not any(name.startswith("crates/") for name in files):
        raise ValueError("Advisory database contains no crate advisories")
    return {"commit": expected, "origin": pin["database_url"], "files_sha256": files}


def update(root, db):
    pin = policy(root)
    db = local_path(root, db)
    receipt = db.with_name(db.name + ".identity.json")
    if db.exists() or receipt.exists():
        raise ValueError("Use a new database destination; previous snapshots are retained")
    db.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".rustsec-", dir=db.parent) as temporary:
        checkout = Path(temporary) / "database"
        subprocess.run(
            ["git", "clone", "--depth", "1", pin["database_url"], str(checkout)], check=True
        )
        commit = git(checkout, "rev-parse", "HEAD").decode().strip()
        identity = database_identity(checkout, commit, pin)
        checkout.rename(db)
    write_new(receipt, {"retrieved_at": now(), **identity})
    return {
        "database": str(db.relative_to(root)),
        "commit": commit,
        "receipt": str(receipt.relative_to(root)),
    }


def run(root, db, commit, output):
    import runtime_inventory

    pin_bytes = (root / POLICY).read_bytes()
    pin = policy(root)
    host_supported(pin)
    binary = tool(root, pin)
    db = Path(os.path.abspath(root / db))
    identity = database_identity(db, commit, pin)
    inventory = runtime_inventory.verify(root)
    before = (root / "Cargo.lock").read_bytes()
    output = local_path(root, output)
    output.mkdir(parents=True, exist_ok=False)
    command = [
        str(binary),
        "audit",
        "--no-fetch",
        "--no-yanked",
        "--db",
        str(db),
        "--file",
        str(root / "Cargo.lock"),
        "--json",
    ]
    result = subprocess.run(command, cwd=root, capture_output=True)
    (output / "cargo-audit.json").write_bytes(result.stdout)
    (output / "stderr.txt").write_bytes(result.stderr)
    if result.returncode not in {0, 1}:
        raise ValueError("cargo-audit failed; retained output is not a completed review")
    report = json.loads(result.stdout)
    settings = report["settings"]
    if any(settings.get(k) for k in ["ignore", "target_arch", "target_os", "severity"]):
        raise ValueError("Implicit audit configuration filtered the review")
    if set(settings.get("informational_warnings", [])) != {"unmaintained", "unsound", "notice"}:
        raise ValueError("Informational audit warnings were filtered")
    vulnerabilities = report["vulnerabilities"]
    count = vulnerabilities["count"]
    if (
        count != len(vulnerabilities["list"])
        or vulnerabilities["found"] != (count > 0)
        or result.returncode != int(count > 0)
    ):
        raise ValueError("cargo-audit status and vulnerability result are inconsistent")
    if (
        (root / "Cargo.lock").read_bytes() != before
        or (root / POLICY).read_bytes() != pin_bytes
        or database_identity(db, commit, pin) != identity
        or runtime_inventory.verify(root) != inventory
        or tool(root, pin) != binary
    ):
        raise ValueError("Audit inputs changed during execution")
    receipt = {
        "schema_version": 1,
        "completed_at": now(),
        "tool_version": pin["version"],
        "tool_sha256": pin["binary_sha256"],
        "policy_sha256": sha(pin_bytes),
        "wrapper_sha256": sha(Path(__file__).read_bytes()),
        "database": identity,
        "cargo_lock_sha256": sha(before),
        "runtime_inventory": inventory,
        "report_sha256": sha(result.stdout),
        "exit_code": result.returncode,
        "network": "disabled by --no-fetch --no-yanked",
        "release_approved": False,
    }
    write_new(output / "receipt.json", receipt)
    return result.returncode, {
        "output": str(output.relative_to(root)),
        "exit_code": result.returncode,
        "vulnerabilities": report["vulnerabilities"]["count"],
        "warnings": {k: len(v) for k, v in report.get("warnings", {}).items()},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("download")
    sub.add_parser("setup").add_argument("--archive", type=Path)
    sub.add_parser("update").add_argument("--db", required=True, type=Path)
    audit = sub.add_parser("run")
    audit.add_argument("--db", required=True, type=Path)
    audit.add_argument("--commit", required=True)
    audit.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.action == "download":
        print(download(ROOT))
    elif args.action == "setup":
        print(json.dumps(setup(ROOT, args.archive), indent=2))
    elif args.action == "update":
        print(json.dumps(update(ROOT, args.db), indent=2))
    else:
        status, summary = run(ROOT, args.db, args.commit, args.output)
        print(json.dumps(summary, indent=2))
        raise SystemExit(status)


if __name__ == "__main__":
    main()
