#!/usr/bin/env python3
"""Build checksum-pinned eSpeak-NG for phonemization only, never device playback."""

import hashlib
import subprocess
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "models/private/espeak"
VERSION = "1.52.0"
SHA256 = "bb4338102ff3b49a81423da8a1a158b420124b055b60fa76cfb4b18677130a23"
BASE.mkdir(parents=True, exist_ok=True)
archive = BASE / "source.tar.gz"
if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
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
endian.write_text(text)
cmake = ["uv", "run", "--with", "cmake==3.31.6", "cmake"]
flags = [
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
variants = sys.argv[1:] or ["host", "aarch64-apple-ios", "aarch64-apple-ios-sim"]
for variant in variants:
    assert variant in ["host", "aarch64-apple-ios", "aarch64-apple-ios-sim"]
    build = BASE / variant
    options = flags.copy()
    if variant != "host":
        sdk = "iphonesimulator" if variant.endswith("sim") else "iphoneos"
        sdk_path = subprocess.check_output(
            ["xcrun", "--sdk", sdk, "--show-sdk-path"], text=True
        ).strip()
        options += [
            "-DCMAKE_SYSTEM_NAME=iOS",
            "-DCMAKE_MACOSX_BUNDLE=OFF",
            f"-DCMAKE_OSX_SYSROOT={sdk_path}",
            "-DCMAKE_OSX_ARCHITECTURES=arm64",
            "-DCMAKE_OSX_DEPLOYMENT_TARGET=26.0",
            "-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY",
        ]
    subprocess.run(cmake + ["-S", str(source), "-B", str(build)] + options, check=True)
    subprocess.run(
        cmake
        + [
            "--build",
            str(build),
            "--parallel",
            "8",
            "--target",
            "data" if variant == "host" else "espeak-ng",
        ],
        check=True,
    )
    assert (build / "src/libespeak-ng/libespeak-ng.a").exists()
print("Pinned eSpeak-NG phonemizer built: " + ", ".join(variants))
