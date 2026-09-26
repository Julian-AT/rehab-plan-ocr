"""Explicit OSV retrieval and strictly offline replay for five Python development locks."""

import argparse
import hashlib
import http.client
import json
import os
import re
import stat
import subprocess
import sys
import time
import tomllib
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCKFILES = (
    "uv.lock",
    "ml/training/assistant/uv.lock",
    "ml/training/ocr/uv.lock",
    "ml/training/assistant/export/uv.lock",
    "tooling/build/export-victoria.py.lock",
)
HOST = "api.osv.dev"
LIMITS = {
    "request_seconds": 30,
    "cleanup_seconds": 2,
    "response_bytes": 8 * 1024**2,
    "total_response_bytes": 128 * 1024**2,
    "input_bytes": 16 * 1024**2,
    "unique_packages": 2000,
    "batch_size": 100,
    "pages_per_query": 20,
    "requests": 4096,
    "advisories": 2048,
}
ADVISORY_FIELDS = {
    "schema_version",
    "id",
    "published",
    "modified",
    "withdrawn",
    "aliases",
    "related",
    "upstream",
    "summary",
    "details",
    "affected",
    "references",
    "severity",
    "credits",
    "database_specific",
}


def encoded(value):
    return (
        json.dumps(value, sort_keys=True, ensure_ascii=False, allow_nan=False, indent=2) + "\n"
    ).encode()


def parsed(raw):
    def unique(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                raise ValueError("Duplicate JSON object key")
            value[key] = item
        return value

    def constant(value):
        raise ValueError(f"Non-JSON numeric constant: {value}")

    return json.loads(raw.decode("utf-8"), object_pairs_hook=unique, parse_constant=constant)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read(path, limit=LIMITS["input_bytes"]):
    if path.is_symlink() or not stat.S_ISREG(path.stat().st_mode):
        raise ValueError(f"Expected regular evidence file: {path}")
    with path.open("rb") as stream:
        value = stream.read(limit + 1)
    if len(value) > limit:
        raise ValueError(f"Evidence exceeds byte limit: {path.name}")
    return value


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with path.open("xb") as stream:
        os.fchmod(stream.fileno(), 0o600)
        stream.write(value)


def private_path(path, root):
    path = path.absolute()
    relative = path.relative_to(root.resolve() / ".local/audits")
    if not relative.parts or ".." in relative.parts:
        raise ValueError("Use a private audit directory below .local/audits")
    for parent in (path, *path.parents):
        if parent.is_symlink():
            raise ValueError("Audit paths must not contain symbolic links")
    return path


def new_output(path, root):
    path = private_path(path, root)
    for parent in path.parents:
        if parent == root.resolve() / ".local/audits":
            break
        if any((parent / marker).exists() for marker in ("receipt.json", "report.json")):
            raise ValueError("Do not create new output inside an existing audit snapshot/report")
    path.mkdir(parents=True, exist_ok=False, mode=0o700)
    return path


def name(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,199}", value):
        raise ValueError("Unsupported PyPI package name")
    return re.sub(r"[-_.]+", "-", value).lower()


def identifier(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,199}", value):
        raise ValueError("Unsupported advisory identifier")
    return value


def timestamp(value):
    if not isinstance(value, str):
        raise ValueError("Missing advisory timestamp")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("Advisory timestamp needs a timezone")
    return parsed


def same_modified(batch, full):
    if batch == full:
        return True
    # OSV's minimal record passes through a Datastore/Python datetime:
    # osv/models.py update_from_vulnerability -> to_vulnerability_minimal.
    # Protobuf ToDatetime truncates nanoseconds to microseconds. Permit only
    # that directed precision loss, without rounding or a time tolerance.
    utc_second = r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}"
    return bool(
        re.fullmatch(utc_second + r"(?:\.[0-9]{1,6})?Z", batch)
        and re.fullmatch(utc_second + r"\.[0-9]{7,9}Z", full)
        and timestamp(batch) == timestamp(full)
    )


def inventory(inputs):
    packages, excluded, headers = {}, [], {}
    if set(inputs) != set(LOCKFILES):
        raise ValueError("The audit requires exactly the five declared lockfiles")
    for lock in LOCKFILES:
        document = tomllib.loads(inputs[lock].decode())
        if type(document.get("version")) is not int or document["version"] != 1:
            raise ValueError("Unsupported uv lock schema")
        if not isinstance(document.get("package"), list) or not document["package"]:
            raise ValueError("Lockfile has no package records")
        headers[lock] = {k: v for k, v in document.items() if k != "package"}
        for index, package in enumerate(document["package"]):
            package_name = name(package["name"])
            version = package.get("version")
            if not isinstance(version, str) or not re.fullmatch(
                r"[A-Za-z0-9][A-Za-z0-9.!+_-]{0,199}", version
            ):
                raise ValueError("Expected an explicit public package version")
            context = {
                "lock": lock,
                "package_index": index,
                "declared_name": package["name"],
                "context": {
                    k: v
                    for k, v in package.items()
                    if k not in {"name", "version", "wheels", "sdist"}
                },
            }
            source = package.get("source")
            if isinstance(source, dict) and set(source) == {"virtual"}:
                virtual = source["virtual"]
                if (
                    not isinstance(virtual, str)
                    or Path(virtual).is_absolute()
                    or ".." in Path(virtual).parts
                    or not virtual
                ):
                    raise ValueError("Unsupported virtual package source")
                excluded.append(
                    {
                        "name": package_name,
                        "version": version,
                        **context,
                        "reason": "local virtual project; not a registry distribution",
                    }
                )
                continue
            if source != {"registry": "https://pypi.org/simple"}:
                raise ValueError(f"Unknown/non-PyPI source in {lock}: package {index}")
            packages.setdefault((package_name, version), []).append(context)
    if not packages or len(packages) > LIMITS["unique_packages"]:
        raise ValueError("Package count outside declared audit bound")
    return {
        "lock_context": headers,
        "excluded_virtual": excluded,
        "packages": [
            {"name": n, "version": v, "occurrences": contexts}
            for (n, v), contexts in sorted(packages.items())
        ],
    }


def inputs_now(root):
    return {lock: read(root / lock) for lock in LOCKFILES}


def unchanged(root, inputs, source):
    if inputs_now(root) != inputs or read(Path(__file__)) != source:
        raise ValueError(
            "Audit source or lockfiles changed; preserve evidence and start a new audit"
        )


def network(method, endpoint, body, destination, limit):
    """Own one HTTP-only child so even blocking system DNS has a wall-clock bound."""
    process = subprocess.Popen(
        [
            sys.executable,
            str(Path(__file__)),
            "_http",
            method,
            endpoint,
            str(destination),
            str(limit),
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    try:
        _, error = process.communicate(body, timeout=LIMITS["request_seconds"])
        if process.returncode:
            raise ValueError("OSV transport failed: " + error.decode(errors="replace").strip())
    except subprocess.TimeoutExpired as error:
        raise TimeoutError("OSV request deadline exceeded; partial response retained") from error
    finally:
        try:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=LIMITS["cleanup_seconds"])
        finally:
            process.stdin.close()
            process.stderr.close()


def http_request(method, endpoint, body, destination, limit):
    """Fixed TLS host, no redirects/auth/proxy discovery; socket deadline and byte cap."""
    end = time.monotonic() + LIMITS["request_seconds"]
    connection = http.client.HTTPSConnection(HOST, timeout=LIMITS["request_seconds"])
    try:
        connection.connect()
        socket = connection.sock

        def remaining():
            seconds = end - time.monotonic()
            if seconds <= 0:
                raise TimeoutError("OSV request deadline exceeded")
            socket.settimeout(seconds)

        remaining()
        connection.request(
            method,
            endpoint,
            body=body,
            headers={"Content-Type": "application/json", "Accept": "application/json"},
        )
        remaining()
        response = connection.getresponse()
        expected_length = response.getheader("Content-Length")
        received = 0
        with destination.open("xb", buffering=0) as stream:
            os.fchmod(stream.fileno(), 0o600)
            while not response.isclosed():
                remaining()
                try:
                    chunk = response.read1(min(64 * 1024, limit - received + 1))
                except http.client.IncompleteRead as error:
                    stream.write(error.partial[: limit - received + 1])
                    raise
                if not chunk:
                    break
                stream.write(chunk)
                received += len(chunk)
                if received > limit:
                    raise ValueError("OSV response exceeds declared byte bound; partial retained")
        if expected_length is not None and (
            not expected_length.isdigit() or int(expected_length) != received
        ):
            raise ValueError("Truncated/invalid OSV Content-Length; partial retained")
        if response.status != 200:
            raise ValueError(f"OSV HTTP status {response.status}; response retained")
    finally:
        connection.close()


def collect(index, exchange):
    """Identical deterministic query/page/GET sequence for retrieval and offline replay."""
    packages = index["packages"]
    pending = [(i, None) for i in range(len(packages))]
    seen_tokens = [set() for _ in packages]
    matches = [{} for _ in packages]
    modified = {}
    while pending:
        following = []
        for start in range(0, len(pending), LIMITS["batch_size"]):
            batch = pending[start : start + LIMITS["batch_size"]]
            queries = []
            for i, token in batch:
                query = {
                    "package": {"ecosystem": "PyPI", "name": packages[i]["name"]},
                    "version": packages[i]["version"],
                }
                if token is not None:
                    query["page_token"] = token
                queries.append(query)
            value = exchange("POST", "/v1/querybatch", {"queries": queries})
            if (
                not isinstance(value, dict)
                or set(value) != {"results"}
                or not isinstance(value["results"], list)
                or len(value["results"]) != len(batch)
            ):
                raise ValueError("OSV batch result length/schema does not match ordered queries")
            for (i, _), result in zip(batch, value["results"], strict=True):
                if not isinstance(result, dict) or set(result) - {"vulns", "next_page_token"}:
                    raise ValueError("Unknown OSV batch result fields")
                vulns = result.get("vulns", [])
                if not isinstance(vulns, list):
                    raise ValueError("Invalid OSV vulnerability list")
                for item in vulns:
                    if not isinstance(item, dict) or set(item) != {"id", "modified"}:
                        raise ValueError("Expected full OSV batch id/modified stub")
                    key, moment = identifier(item["id"]), item["modified"]
                    timestamp(moment)
                    if key in matches[i] or (key in modified and modified[key] != moment):
                        raise ValueError(
                            "Duplicated or changing advisory identity across query pages"
                        )
                    matches[i][key] = item["modified"]
                    modified[key] = moment
                    if len(modified) > LIMITS["advisories"]:
                        raise ValueError("Advisory count exceeds declared bound")
                token = result.get("next_page_token", "")
                if not isinstance(token, str) or len(token) > 4096:
                    raise ValueError("Invalid OSV page token")
                if token:
                    if (
                        token in seen_tokens[i]
                        or len(seen_tokens[i]) >= LIMITS["pages_per_query"] - 1
                    ):
                        raise ValueError("Repeated/excessive OSV pagination; download incomplete")
                    seen_tokens[i].add(token)
                    following.append((i, token))
        pending = following
    records = {}
    for key in sorted(modified):
        record = exchange("GET", "/v1/vulns/" + key, None)
        if not isinstance(record, dict) or set(record) - ADVISORY_FIELDS or record.get("id") != key:
            raise ValueError("Wrong advisory identity or unsupported OSV record fields")
        timestamp(record.get("modified"))
        if not same_modified(modified[key], record["modified"]):
            raise ValueError("Advisory changed between batch query and full retrieval")
        if "withdrawn" in record:
            timestamp(record["withdrawn"])
        aliases = record.get("aliases", [])
        if not isinstance(aliases, list) or len(aliases) != len(set(aliases)):
            raise ValueError("Invalid advisory aliases")
        for alias in aliases:
            identifier(alias)
        affected = record.get("affected", [])
        if not isinstance(affected, list) or (not affected and "withdrawn" not in record):
            raise ValueError("Full active advisory needs affected package records")
        affected_names = set()
        for item in affected:
            if not isinstance(item, dict) or set(item) - {
                "package",
                "ranges",
                "versions",
                "ecosystem_specific",
                "database_specific",
                "severity",
            }:
                raise ValueError("Unsupported affected-package record")
            package = item.get("package")
            if not isinstance(package, dict) or set(package) - {"name", "ecosystem", "purl"}:
                raise ValueError("Missing/unknown affected package identity")
            if package.get("ecosystem") == "PyPI":
                affected_names.add(name(package.get("name")))
        for i, matched in enumerate(matches):
            if (
                key in matched
                and "withdrawn" not in record
                and packages[i]["name"] not in affected_names
            ):
                raise ValueError("Batch order/advisory package identity mismatch")
        records[key] = record
    return matches, records


def file_manifest(output):
    result = {}
    for path in sorted(output.rglob("*")):
        if path.is_symlink():
            raise ValueError("Snapshot contains a symbolic link")
        if path.is_file() and path != output / "receipt.json":
            data = read(path)
            result[str(path.relative_to(output))] = {"sha256": sha(data), "bytes": len(data)}
        elif path != output / "receipt.json" and not path.is_dir():
            raise ValueError("Snapshot contains a non-regular evidence entry")
    return result


def download(output, root=ROOT, transport=network):
    output = new_output(output, root)
    receipt = {
        "schema_version": 1,
        "kind": "python-osv-download",
        "status": "incomplete",
        "completed": False,
        "origin": "https://" + HOST,
        "limits": LIMITS,
        "retrieved_at_utc": datetime.now(timezone.utc).isoformat(),
        "python": sys.version,
        "exchanges": [],
        "advisory_sha256": {},
        "qualified": False,
    }
    try:
        source, inputs = read(Path(__file__)), inputs_now(root)
        write(output / "source/audit_python.py", source)
        for i, lock in enumerate(LOCKFILES):
            write(output / f"locks/{i}.lock", inputs[lock])
        receipt["source_sha256"] = sha(source)
        receipt["locks"] = {
            lock: {"path": f"locks/{i}.lock", "sha256": sha(inputs[lock])}
            for i, lock in enumerate(LOCKFILES)
        }
        index = inventory(inputs)
        write(output / "inventory.json", encoded(index))
        total_bytes = 0

        def exchange(method, endpoint, payload):
            nonlocal total_bytes
            sequence = len(receipt["exchanges"])
            if sequence >= LIMITS["requests"]:
                raise ValueError("OSV request count exceeds declared bound")
            request = {"method": method, "endpoint": endpoint, "body": payload}
            body = encoded(payload) if payload is not None else None
            item = {
                "request": f"requests/{sequence:04d}.json",
                "response": f"responses/{sequence:04d}.json",
                "body_sha256": sha(body or b""),
            }
            receipt["exchanges"].append(item)
            write(output / item["request"], encoded(request))
            response_path = output / item["response"]
            response_path.parent.mkdir(exist_ok=True, mode=0o700)
            bound = min(LIMITS["response_bytes"], LIMITS["total_response_bytes"] - total_bytes)
            if bound <= 0:
                raise ValueError("OSV total response byte bound reached")
            transport(method, endpoint, body, response_path, bound)
            raw = read(response_path, bound)
            total_bytes += len(raw)
            if method == "GET":
                receipt["advisory_sha256"][endpoint.removeprefix("/v1/vulns/")] = sha(raw)
            return parsed(raw)

        matches, records = collect(index, exchange)
        unchanged(root, inputs, source)
        receipt.update(
            completed=True,
            status="complete",
            package_versions=len(matches),
            advisory_records=len(records),
        )
    except BaseException as error:
        receipt["error"] = f"{type(error).__name__}: {error}"
        raise
    finally:
        try:
            receipt["files"] = file_manifest(output)
        except Exception as error:
            receipt.update(completed=False, status="incomplete", manifest_error=str(error))
            raise
        finally:
            write(output / "receipt.json", encoded(receipt))
    return receipt


def findings(index, matches, records):
    groups = []
    for key, record in records.items():
        identities = {key, *record.get("aliases", [])}
        matching = [g for g in groups if g["identities"] & identities]
        group = {"identities": identities, "ids": {key}}
        for other in matching:
            group["identities"].update(other["identities"])
            group["ids"].update(other["ids"])
            groups.remove(other)
        groups.append(group)
    result = []
    for group in groups:
        active = {key for key in group["ids"] if "withdrawn" not in records[key]}
        affected = [i for i, match in enumerate(matches) if set(match) & group["ids"]]
        active_affected = [i for i, match in enumerate(matches) if set(match) & active]
        result.append(
            {
                "advisory_ids": sorted(group["ids"]),
                "aliases": sorted(group["identities"] - group["ids"]),
                "status": "active" if active else "withdrawn",
                "package_indices": affected,
                "active_package_indices": active_affected,
            }
        )
    result.sort(key=lambda item: item["advisory_ids"])
    return {
        "packages": index["packages"],
        "excluded_virtual": index["excluded_virtual"],
        "lock_context": index["lock_context"],
        "matches_in_query_order": matches,
        "advisories": records,
        "vulnerability_groups": result,
        "counts": {
            "queried_package_versions": len(matches),
            "registry_occurrences": sum(len(p["occurrences"]) for p in index["packages"]),
            "excluded_virtual": len(index["excluded_virtual"]),
            "advisory_records": len(records),
            "withdrawn_records": sum("withdrawn" in r for r in records.values()),
            "active_advisory_records": sum("withdrawn" not in r for r in records.values()),
            "affected_package_versions": sum(bool(match) for match in matches),
            "active_vulnerability_groups": sum(g["status"] == "active" for g in result),
            "withdrawn_only_groups": sum(g["status"] == "withdrawn" for g in result),
            "active_affected_package_versions": len(
                {i for g in result for i in g["active_package_indices"]}
            ),
        },
    }


def offline(snapshot, snapshot_sha256, output, root=ROOT):
    output = new_output(output, root)
    report = {
        "schema_version": 1,
        "complete": False,
        "passed": False,
        "qualified": False,
        "status": "failed",
        "snapshot_sha256": snapshot_sha256,
    }
    try:
        snapshot = private_path(snapshot, root)
        raw_receipt = read(snapshot / "receipt.json")
        if sha(raw_receipt) != snapshot_sha256:
            raise ValueError("Snapshot receipt does not match the explicit expected hash")
        receipt = parsed(raw_receipt)
        if (
            receipt.get("kind") != "python-osv-download"
            or receipt.get("schema_version") != 1
            or receipt.get("status") != "complete"
            or receipt.get("completed") is not True
            or receipt.get("limits") != LIMITS
            or receipt.get("origin") != "https://" + HOST
        ):
            raise ValueError("Snapshot is incomplete or has a different audit contract")
        if file_manifest(snapshot) != receipt["files"]:
            raise ValueError("Snapshot files changed or are missing/unexpected")
        expected_files = {
            "source/audit_python.py",
            "inventory.json",
            *(f"locks/{i}.lock" for i in range(len(LOCKFILES))),
        }
        for i in range(len(receipt["exchanges"])):
            expected_files.update({f"requests/{i:04d}.json", f"responses/{i:04d}.json"})
        if (
            set(receipt["files"]) != expected_files
            or len(receipt["exchanges"]) > LIMITS["requests"]
        ):
            raise ValueError("Snapshot file closure/request bound changed")
        source, inputs = read(Path(__file__)), inputs_now(root)
        expected_locks = {
            lock: {"path": f"locks/{i}.lock", "sha256": sha(inputs[lock])}
            for i, lock in enumerate(LOCKFILES)
        }
        if (
            receipt["source_sha256"] != sha(source)
            or read(snapshot / "source/audit_python.py") != source
            or receipt["locks"] != expected_locks
        ):
            raise ValueError("Current audit source/locks do not match the saved identity")
        for i, lock in enumerate(LOCKFILES):
            if read(snapshot / f"locks/{i}.lock") != inputs[lock]:
                raise ValueError("Archived lockfile does not match current identity")
        index = inventory(inputs)
        if read(snapshot / "inventory.json") != encoded(index):
            raise ValueError("Saved inventory differs from the bound lockfiles")
        position = 0
        total_bytes = 0
        advisory_hashes = {}

        def replay(method, endpoint, payload):
            nonlocal position, total_bytes
            if position >= len(receipt["exchanges"]):
                raise ValueError("Incomplete recorded request sequence")
            item = receipt["exchanges"][position]
            expected = {
                "request": f"requests/{position:04d}.json",
                "response": f"responses/{position:04d}.json",
                "body_sha256": sha(encoded(payload) if payload is not None else b""),
            }
            if item != expected or read(snapshot / expected["request"]) != encoded(
                {"method": method, "endpoint": endpoint, "body": payload}
            ):
                raise ValueError("Recorded query ordering, pagination or identity changed")
            position += 1
            raw = read(snapshot / expected["response"], LIMITS["response_bytes"])
            total_bytes += len(raw)
            if total_bytes > LIMITS["total_response_bytes"]:
                raise ValueError("Saved responses exceed total byte bound")
            if method == "GET":
                advisory_hashes[endpoint.removeprefix("/v1/vulns/")] = sha(raw)
            return parsed(raw)

        matches, records = collect(index, replay)
        if (
            position != len(receipt["exchanges"])
            or len(matches) != receipt["package_versions"]
            or len(records) != receipt["advisory_records"]
            or advisory_hashes != receipt["advisory_sha256"]
        ):
            raise ValueError("Unexpected/omitted recorded exchanges or result counts")
        result = findings(index, matches, records)
        unchanged(root, inputs, source)
        if (
            read(snapshot / "receipt.json") != raw_receipt
            or file_manifest(snapshot) != receipt["files"]
        ):
            raise ValueError("Snapshot changed during offline replay")
        passed = result["counts"]["active_vulnerability_groups"] == 0
        report.update(
            result,
            complete=True,
            passed=passed,
            status="complete-no-active-findings" if passed else "complete-with-findings",
            source_sha256=sha(source),
            lock_sha256={k: sha(v) for k, v in inputs.items()},
            advisory_sha256=advisory_hashes,
        )
    except BaseException as error:
        report["error"] = f"{type(error).__name__}: {error}"
        raise
    finally:
        write(output / "report.json", encoded(report))
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    commands = parser.add_subparsers(dest="action", required=True)
    fetch = commands.add_parser(
        "download",
        help="Explicit online query; transmits only public PyPI names/versions and OSV IDs/tokens",
    )
    fetch.add_argument("--output", type=Path, required=True)
    replay = commands.add_parser("offline", help="Replay saved responses without network access")
    replay.add_argument("--snapshot", type=Path, required=True)
    replay.add_argument("--snapshot-sha256", required=True)
    replay.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.action == "download":
            result = download(args.output, args.root)
            result = {
                "status": result["status"],
                "snapshot_sha256": sha(read(args.output / "receipt.json")),
            }
            code = 0
        else:
            result = offline(args.snapshot, args.snapshot_sha256, args.output, args.root)
            code = 0 if result["passed"] else 1
        print(json.dumps(result, sort_keys=True))
        return code
    except Exception as error:
        print(f"Python dependency audit incomplete: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    if sys.argv[1:2] == ["_http"]:
        try:
            _, _, method, endpoint, destination, bound = sys.argv
            body = sys.stdin.buffer.read(256 * 1024 + 1)
            if len(body) > 256 * 1024:
                raise ValueError("OSV request body exceeds internal bound")
            http_request(method, endpoint, body or None, Path(destination), int(bound))
        except Exception as error:
            print(f"{type(error).__name__}: {error}", file=sys.stderr)
            raise SystemExit(2) from error
        raise SystemExit(0)
    raise SystemExit(main())
