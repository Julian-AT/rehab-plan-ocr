#!/usr/bin/env python3
"""Explicit, cached builds of the pinned local phonemizer; --verify never writes."""

import argparse
import hashlib
import json
import subprocess
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / ".local/models/runtime/espeak"
BUILD_BASE = ROOT / ".local/builds/phonemizer"
VERSION = "1.52.0"
SHA256 = "bb4338102ff3b49a81423da8a1a158b420124b055b60fa76cfb4b18677130a23"
VARIANTS = ["host", "aarch64-apple-ios", "aarch64-apple-ios-sim"]
LIBRARIES = ("src/libespeak-ng/libespeak-ng.a", "src/ucd-tools/libucd.a")


def sha(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def prepare_source(offline):
    BASE.mkdir(parents=True, exist_ok=True)
    archive = BASE / "source.tar.gz"
    if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        if offline:
            raise RuntimeError(
                "Pinned phonemizer source missing; run make restore-experimental-speech."
            )
        temporary = archive.with_suffix(".download")
        subprocess.run(
            [
                "curl",
                "--fail",
                "--location",
                "--silent",
                "--show-error",
                "--retry",
                "3",
                f"https://codeload.github.com/espeak-ng/espeak-ng/tar.gz/refs/tags/{VERSION}",
                "--output",
                str(temporary),
            ],
            check=True,
        )
        assert hashlib.sha256(temporary.read_bytes()).hexdigest() == SHA256, (
            "eSpeak source checksum mismatch"
        )
        temporary.replace(archive)
    source = BASE / f"espeak-ng-{VERSION}"
    if not source.exists():
        with tarfile.open(archive) as package:
            package.extractall(BASE, filter="data")
    # Upstream downloads Sonic even with USE_LIBSONIC=OFF. Avoid that unused network
    # dependency. Both source patches are completely tracked here.
    deps = source / "cmake/deps.cmake"
    text = deps.read_text()
    text = text.replace(
        "else()\n  FetchContent_Declare(sonic-git",
        "elseif(NOT DEFINED USE_LIBSONIC OR USE_LIBSONIC)\n  FetchContent_Declare(sonic-git",
    )
    if deps.read_text() != text:
        deps.write_text(text)
    # New Apple SDKs provide endian.h without Linux-style le16toh/le32toh.
    # Always use upstream's existing OSByteOrder implementation on Apple.
    endian = source / "src/include/compat/endian.h"
    text = endian.read_text().replace(
        "#if __has_include_next(<endian.h>)",
        "#if !defined(__APPLE__) && __has_include_next(<endian.h>)",
    )
    text = text.replace(
        "#elif __has_include(<sys/endian.h>)",
        "#elif !defined(__APPLE__) && __has_include(<sys/endian.h>)",
    )
    if endian.read_text() != text:
        endian.write_text(text)
    return source


FLAGS = [
    "-DCMAKE_BUILD_TYPE=Release",
    "-DCMAKE_C_FLAGS=-DN_PATH_HOME=1024",
    "-DBUILD_SHARED_LIBS=OFF",
    "-DUSE_LIBPCAUDIO=OFF",
    "-DUSE_LIBSONIC=OFF",
    "-DUSE_MBROLA=OFF",
    "-DUSE_SPEECHPLAYER=OFF",
    "-DUSE_ASYNC=OFF",
    "-DBUILD_TESTING=OFF",
]


def configuration(variant):
    options = FLAGS.copy()
    toolchain = subprocess.check_output(["xcrun", "clang", "--version"], text=True).strip()
    if variant != "host":
        sdk = "iphonesimulator" if variant.endswith("sim") else "iphoneos"
        sdk_path = subprocess.check_output(
            ["xcrun", "--sdk", sdk, "--show-sdk-path"], text=True
        ).strip()
        sdk_version = subprocess.check_output(
            ["xcrun", "--sdk", sdk, "--show-sdk-build-version"], text=True
        ).strip()
        toolchain += "\n" + sdk_version
        options += [
            "-DCMAKE_SYSTEM_NAME=iOS",
            "-DCMAKE_MACOSX_BUNDLE=OFF",
            f"-DCMAKE_OSX_SYSROOT={sdk_path}",
            "-DCMAKE_OSX_ARCHITECTURES=arm64",
            "-DCMAKE_OSX_DEPLOYMENT_TARGET=26.0",
            "-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY",
        ]
    return options, toolchain


def identity(source, variant, options, toolchain):
    digest = hashlib.sha256()
    for path in sorted(source.rglob("*")):
        if path.is_file():
            digest.update(str(path.relative_to(source)).encode() + b"\0")
            digest.update(bytes.fromhex(sha(path)))
    return {
        "variant": variant,
        "source_archive_sha256": SHA256,
        "source_tree_sha256": digest.hexdigest(),
        "builder_sha256": sha(Path(__file__)),
        "toolchain": toolchain,
        "cmake": "3.31.6",
        "options": options,
    }


def cache_matches(build, expected):
    receipt = build / "build-identity.json"
    if not receipt.is_file():
        return False
    try:
        record = json.loads(receipt.read_text())
        return (
            record["identity"] == expected
            and all(
                (build / name).is_file() and sha(build / name) == digest
                for name, digest in record["artifacts"].items()
            )
            and set(LIBRARIES) <= record["artifacts"].keys()
        )
    except (ValueError, KeyError, OSError):
        return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("variants", choices=VARIANTS, nargs="*")
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    source = BASE / f"espeak-ng-{VERSION}"
    if args.verify:
        if not source.is_dir():
            raise RuntimeError("Phonemizer source missing; run make restore and make convert.")
    else:
        source = prepare_source(args.offline)
    if args.source_only:
        if args.verify:
            raise ValueError("--source-only cannot be combined with --verify")
        return
    cmake = [
        "uv",
        "run",
        "--locked",
        *(["--offline"] if args.offline else []),
        "--with",
        "cmake==3.31.6",
        "cmake",
    ]
    for variant in args.variants or VARIANTS:
        build = BUILD_BASE / variant
        options, toolchain = configuration(variant)
        expected = identity(source, variant, options, toolchain)
        if cache_matches(build, expected):
            print(f"Verified cached phonemizer: {variant}")
            continue
        if args.verify:
            raise RuntimeError(
                f"Phonemizer cache missing or stale for {variant}; run make convert."
            )
        subprocess.run(cmake + ["-S", str(source), "-B", str(build)] + options, check=True)
        subprocess.run(
            cmake
            + [
                "--build",
                str(build),
                "--parallel",
                "4",
                "--target",
                "data" if variant == "host" else "espeak-ng",
            ],
            check=True,
        )
        artifacts = {name: sha(build / name) for name in LIBRARIES}
        if variant == "host":
            artifacts.update(
                {
                    str(path.relative_to(build)): sha(path)
                    for path in (build / "espeak-ng-data").rglob("*")
                    if path.is_file()
                }
            )
        receipt = build / "build-identity.json"
        temporary = receipt.with_suffix(".tmp")
        temporary.write_text(
            json.dumps({"identity": expected, "artifacts": artifacts}, indent=2) + "\n"
        )
        temporary.replace(receipt)
        print(f"Built and recorded phonemizer: {variant}")


if __name__ == "__main__":
    main()
