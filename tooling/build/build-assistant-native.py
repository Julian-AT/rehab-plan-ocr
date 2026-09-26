"""Build the pinned experimental assistant C boundary for Apple targets, offline.

No training package becomes an application dependency. CPU execution is the initial
compatibility route; promotion and Metal/resource comparisons are separate gates.
"""

import argparse
import fcntl
import importlib.util
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "packages/apple/LocalAssistant"
SOURCE = ROOT / ".local/upstream/llama.cpp"
BASE = ROOT / ".local/builds/assistant-native"
REGISTRY = ROOT / "ml/registry/assistant-base.json"
CMAKE = [str(ROOT / ".tools/bin/uv"), "run", "--locked", "--with", "cmake==3.31.6", "cmake"]
VARIANTS = {"host": "macosx", "simulator": "iphonesimulator", "device": "iphoneos"}
spec = importlib.util.spec_from_file_location(
    "native_assembly", Path(__file__).with_name("assemble-native.py")
)
assembly = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assembly)


def run(*args, capture=False):
    result = subprocess.run(
        args,
        cwd=ROOT,
        env=dict(os.environ, UV_OFFLINE="1"),
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
    )
    return result.stdout.strip() if capture else None


def build(variant):
    registry = json.loads(REGISTRY.read_text())
    revision = run("git", "-C", str(SOURCE), "rev-parse", "HEAD", capture=True)
    if revision != registry["converter_revision"] or run(
        "git", "-C", str(SOURCE), "status", "--porcelain", capture=True
    ):
        raise ValueError("Assistant source differs from its pinned unmodified revision")
    sdk = VARIANTS[variant]
    flags = [
        "-DCMAKE_BUILD_TYPE=Release",
        "-DBUILD_SHARED_LIBS=OFF",
        "-DLLAMA_BUILD_APP=OFF",
        "-DLLAMA_BUILD_COMMON=OFF",
        "-DLLAMA_BUILD_EXAMPLES=OFF",
        "-DLLAMA_BUILD_TOOLS=OFF",
        "-DLLAMA_BUILD_TESTS=OFF",
        "-DLLAMA_BUILD_SERVER=OFF",
        "-DLLAMA_BUILD_MTMD=OFF",
        "-DGGML_METAL=OFF",
        "-DGGML_BLAS=OFF",
        "-DGGML_ACCELERATE=ON",
        "-DGGML_NATIVE=OFF",
        "-DGGML_OPENMP=OFF",
        "-DGGML_CPU_KLEIDIAI=OFF",
        "-DCMAKE_OSX_ARCHITECTURES=arm64",
        f"-DCMAKE_OSX_SYSROOT={sdk}",
        "-DCMAKE_OSX_DEPLOYMENT_TARGET=26.0",
    ]
    if variant != "host":
        flags += ["-DCMAKE_SYSTEM_NAME=iOS", "-DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO"]
    identity = {
        "kind": "experimental-CPU-assistant",
        "variant": variant,
        "source_revision": revision,
        "flags": flags,
        "compiler": run("xcrun", "clang", "--version", capture=True),
        "sdk": run("xcrun", "--sdk", sdk, "--show-sdk-build-version", capture=True),
        "cmake": run(*CMAKE, "--version", capture=True),
        "builder_sha256": assembly.sha(Path(__file__)),
        "cache_helper_sha256": assembly.sha(Path(__file__).with_name("assemble-native.py")),
        "sources": {
            str(p.relative_to(PACKAGE)): assembly.sha(p)
            for p in sorted((PACKAGE / "Native").rglob("*"))
            if p.is_file()
        },
    }

    def produce(destination):
        with tempfile.TemporaryDirectory(prefix=".compile-", dir=BASE) as temporary:
            build = Path(temporary)
            run(
                *CMAKE,
                "-S",
                str(PACKAGE / "Native"),
                "-B",
                str(build),
                f"-DLLAMA_SOURCE={SOURCE}",
                *flags,
            )
            run(*CMAKE, "--build", str(build), "--target", "RehaAssistantNative", "-j", "4")
            libraries = sorted(build.rglob("*.a"))
            if not {
                "libRehaAssistantNative.a",
                "libllama.a",
                "libggml.a",
                "libggml-base.a",
                "libggml-cpu.a",
            } <= {p.name for p in libraries}:
                raise ValueError("Assistant native build omitted a required static library")
            run(
                "xcrun",
                "libtool",
                "-static",
                "-o",
                str(destination / "libRehaAssistantNative.a"),
                *map(str, libraries),
            )
        headers = destination / "Headers"
        shutil.copytree(PACKAGE / "Native/include", headers)
        (headers / "module.modulemap").write_text(
            'module RehaAssistantNative {\n  header "RehaAssistantNative.h"\n  link "c++"\n  link framework "Accelerate"\n  export *\n}\n'
        )
        shutil.copyfile(SOURCE / "LICENSE", destination / "llama-license.txt")

    return assembly.cached_build(
        BASE / "libraries",
        identity,
        {
            "libRehaAssistantNative.a",
            "Headers/RehaAssistantNative.h",
            "Headers/module.modulemap",
            "llama-license.txt",
        },
        produce,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("variants", nargs="+", choices=VARIANTS)
    args = parser.parse_args()
    BASE.mkdir(parents=True, exist_ok=True)
    with (BASE / "assembly.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        libraries = {variant: build(variant) for variant in sorted(set(args.variants))}
        identity = {v: json.loads((p / "receipt.json").read_text()) for v, p in libraries.items()}

        def produce(destination):
            command = ["xcodebuild", "-create-xcframework"]
            # Framework modules have their own namespace. Two flat static-library
            # XCFrameworks would both publish include/module.modulemap in Xcode.
            for variant, path in libraries.items():
                product = destination / variant / "RehaAssistantNative.framework"
                headers = product / "Headers"
                modules = product / "Modules"
                headers.mkdir(parents=True)
                modules.mkdir()
                shutil.copyfile(path / "libRehaAssistantNative.a", product / "RehaAssistantNative")
                shutil.copyfile(
                    path / "Headers/RehaAssistantNative.h", headers / "RehaAssistantNative.h"
                )
                (modules / "module.modulemap").write_text(
                    'framework module RehaAssistantNative {\n  umbrella header "RehaAssistantNative.h"\n  link "c++"\n  link framework "Accelerate"\n  export *\n}\n'
                )
                (product / "Info.plist").write_bytes(
                    plistlib.dumps(
                        {
                            "CFBundleIdentifier": "at.rehakalender.runtime.assistant",
                            "CFBundleExecutable": "RehaAssistantNative",
                            "CFBundleName": "RehaAssistantNative",
                            "CFBundlePackageType": "FMWK",
                            "CFBundleVersion": "1",
                            "CFBundleShortVersionString": "1.0",
                            "MinimumOSVersion": "26.0",
                            "CFBundleSupportedPlatforms": [
                                {
                                    "host": "MacOSX",
                                    "simulator": "iPhoneSimulator",
                                    "device": "iPhoneOS",
                                }[variant]
                            ],
                        }
                    )
                )
                command += ["-framework", str(product)]
            run(*command, "-output", str(destination / "RehaAssistantNative.xcframework"))
            for variant in libraries:
                shutil.rmtree(destination / variant)

        framework = assembly.cached_build(
            BASE / "frameworks", identity, {"RehaAssistantNative.xcframework/Info.plist"}, produce
        )
        assembly.publish_link(
            PACKAGE / "RehaAssistantNative.xcframework",
            framework / "RehaAssistantNative.xcframework",
        )
        print(
            json.dumps(
                {
                    "variants": {v: str(p.relative_to(ROOT)) for v, p in libraries.items()},
                    "framework": str(framework.relative_to(ROOT)),
                }
            )
        )


if __name__ == "__main__":
    main()
