"""Assemble verified native archives without touching unchanged build products.

Cargo remains responsible for compilation. This cache keys the actual compiled
archives, pinned model manifests, headers, source and Apple/Rust toolchains. Every
cache hit verifies all output bytes. Only complete, validated products are exposed
through the package's ignored XCFramework link.
"""

import argparse
import fcntl
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tooling/release"))
from runtime_policy import MODELS, check_binary  # noqa: E402
from runtime_policy import check_symbols as check_release_symbols  # noqa: E402

VARIANTS = {"device": "aarch64-apple-ios", "simulator": "aarch64-apple-ios-sim"}


def sha(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def tree(path):
    files = {}
    for item in sorted(path.rglob("*")):
        if item.is_symlink():
            raise ValueError(f"Generated cache contains an unexpected symbolic link: {item}")
        if item.is_file() and item != path / "receipt.json":
            files[str(item.relative_to(path))] = sha(item)
    return files


def key(identity):
    return hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()


def matches(destination, identity, required):
    try:
        receipt = json.loads((destination / "receipt.json").read_text())
        return (
            receipt["identity"] == identity
            and set(required) <= receipt["artifacts"].keys()
            and tree(destination) == receipt["artifacts"]
        )
    except (OSError, ValueError, KeyError, TypeError):
        return False


def cached_build(base, identity, required, produce):
    """Caller serializes builders; failed production leaves the previous entry intact."""
    base.mkdir(parents=True, exist_ok=True)
    destination = base / key(identity)
    if matches(destination, identity, required):
        print(f"Verified native assembly cache: {destination.name}", flush=True)
        return destination
    with tempfile.TemporaryDirectory(prefix=".assembly-", dir=base) as temporary:
        staging = Path(temporary) / "product"
        staging.mkdir()
        produce(staging)
        artifacts = tree(staging)
        if not set(required) <= artifacts.keys():
            raise ValueError("Native builder omitted a required artifact")
        (staging / "receipt.json").write_text(
            json.dumps({"identity": identity, "artifacts": artifacts}, indent=2) + "\n"
        )
        if not matches(staging, identity, required):
            raise ValueError("Native assembly failed verification before publication")
        previous = Path(temporary) / "previous"
        if destination.exists():
            destination.rename(previous)
        try:
            staging.rename(destination)
        except BaseException:
            if previous.exists():
                previous.rename(destination)
            raise
    print(f"Built native assembly cache: {destination.name}", flush=True)
    return destination


def publish_link(destination, product):
    if destination.is_symlink() and destination.resolve() == product.resolve():
        return
    link = destination.with_name(f".{destination.name}.{uuid.uuid4().hex}")
    link.symlink_to(os.path.relpath(product, destination.parent), target_is_directory=True)
    # One-time migration of the old, generated directory. Future publications
    # replace the symlink atomically without moving or copying the cached product.
    previous = destination.with_name(f".{destination.name}.previous-{uuid.uuid4().hex}")
    moved = destination.is_dir() and not destination.is_symlink()
    try:
        if moved:
            destination.rename(previous)
        try:
            link.replace(destination)
        except BaseException:
            if moved:
                previous.rename(destination)
            raise
        if moved:
            shutil.rmtree(previous)
    finally:
        link.unlink(missing_ok=True)


def output(*command):
    return subprocess.check_output(command, cwd=ROOT, text=True).strip()


def check_symbols(result):
    check_release_symbols(result.stdout.encode())
    # Apple's nm cannot decode some Rust 1.98 LLVM 22 bitcode attributes.
    # ONNX Runtime is native Mach-O and must still expose its API symbol.
    diagnostics = [
        line
        for line in result.stderr.splitlines()
        if line.strip() and not line.endswith(".o: no symbols")
    ]
    known_bitcode = all(
        ": Unknown attribute kind (" in line and "-rust-" in line for line in diagnostics
    )
    if result.returncode and (not diagnostics or not known_bitcode):
        raise ValueError(f"Cannot inspect native symbols: {result.stderr}")
    if not any(line.endswith(" T _OrtGetApiBase") for line in result.stdout.splitlines()):
        raise ValueError("Assembled native library is missing ONNX Runtime")


def assemble(root, variants):
    cache = root / ".local/builds/ffi"
    cache.mkdir(parents=True, exist_ok=True)
    with (cache / "assembly.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        headers = root / "packages/apple/RehaCore/Headers"
        sources = [
            root / "Cargo.toml",
            root / "Cargo.lock",
            root / "config/toolchains/versions.json",
            root / "tooling/release/runtime_policy.py",
        ]
        for package in ["reha-core", "reha-ffi"]:
            sources.extend(
                p
                for p in (root / "packages/rust" / package).rglob("*")
                if p.is_file() and p.suffix in {".rs", ".toml", ".udl"}
            )
        sources.extend(
            root / "ml/registry/runtime" / f"{model}.lock.json"
            for model in [*MODELS, "ios-runtime"]
        )
        common = {
            "version": 1,
            "builder_sha256": sha(Path(__file__)),
            "inputs": {str(p.relative_to(root)): sha(p) for p in sorted(sources)},
            "xcode": output("xcodebuild", "-version"),
            "rust": output("rustc", "-vV"),
            "libtool": output("xcrun", "libtool", "-V"),
            "headers": tree(headers),
            "deployment_target": "26.0",
        }
        libraries = {}
        for variant in sorted(variants):
            triple = VARIANTS[variant]
            archive = root / "target" / triple / "release/libreha_ffi.a"
            runtime = root / ".local/models/runtime/runtime" / triple / "libonnxruntime.a"
            sdk = "iphonesimulator" if variant == "simulator" else "iphoneos"
            identity = common | {
                "triple": triple,
                "sdk": output("xcrun", "--sdk", sdk, "--show-sdk-build-version"),
                "archive_sha256": sha(archive),
                "runtime_sha256": sha(runtime),
            }

            def produce(staging, archive=archive, runtime=runtime):
                library = staging / "libRehaCoreFFI.a"
                subprocess.run(
                    ["xcrun", "libtool", "-static", "-o", library, archive, runtime], check=True
                )
                if output("xcrun", "lipo", "-archs", str(library)) != "arm64":
                    raise ValueError("Unexpected architecture in assembled native library")
                symbols = subprocess.run(
                    ["xcrun", "nm", "-g", library], text=True, capture_output=True, check=False
                )
                check_symbols(symbols)
                check_binary(library)
                (staging / "nm-diagnostics.txt").write_text(symbols.stderr)

            libraries[variant] = cached_build(
                cache / "libraries", identity, ["libRehaCoreFFI.a"], produce
            )
        identity = common | {
            "libraries": {variant: directory.name for variant, directory in libraries.items()}
        }

        def framework(staging):
            command = ["xcodebuild", "-create-xcframework"]
            for directory in libraries.values():
                command.extend(["-library", directory / "libRehaCoreFFI.a", "-headers", headers])
            subprocess.run(command + ["-output", staging / "RehaCoreFFI.xcframework"], check=True)

        product = cached_build(
            cache / "frameworks", identity, ["RehaCoreFFI.xcframework/Info.plist"], framework
        )
        publish_link(
            root / "packages/apple/RehaCore/RehaCoreFFI.xcframework",
            product / "RehaCoreFFI.xcframework",
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("variants", choices=VARIANTS, nargs="+")
    args = parser.parse_args()
    assemble(ROOT, set(args.variants))


if __name__ == "__main__":
    main()
