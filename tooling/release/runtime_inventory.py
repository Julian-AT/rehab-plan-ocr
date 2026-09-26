"""Generate or verify the actual iOS dependency closure and its bundled notices.

Normal builds only verify committed inputs/outputs. Generation is an explicit,
offline operation using Cargo's selected target tree and restored crate sources.
This inventory records declarations and evidence; it does not grant redistribution rights.
"""

import argparse
import hashlib
import json
import plistlib
import re
import subprocess
import tomllib
from collections import defaultdict
from pathlib import Path

from runtime_policy import check_features

ROOT = Path(__file__).resolve().parents[2]
NOTICES = "docs/third-party/licenses"
COMBINED = "rust-dependencies.txt"
INVENTORY = "docs/third-party/runtime-inventory.json"
TARGET = "aarch64-apple-ios"


def encoded(value):
    return (json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n").encode()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def command(*args):
    return subprocess.run(args, cwd=ROOT, check=True, capture_output=True, text=True).stdout


def selected_tree(text):
    """Metadata can contain inactive optional packages; Cargo tree selects the build."""
    selected = defaultdict(set)
    for line in text.splitlines():
        match = re.fullmatch(r"(\S+) v(\S+)[^|]*\|(.*)", line)
        if not match:
            raise ValueError(f"Unexpected Cargo tree record: {line}")
        features = match[3].removesuffix(" (*)")
        selected[(match[1], match[2])].update(filter(None, features.split(",")))
    if not selected:
        raise ValueError("The iOS dependency tree is empty")
    return selected


def notice_sources(package, root):
    source = Path(package["manifest_path"]).parent
    files = {
        p
        for p in source.iterdir()
        if p.is_file() and p.name.lower().startswith(("license", "copying", "notice", "copyright"))
    }
    if package.get("license_file"):
        files.add(source / package["license_file"])
    if files:
        notices = []
        for path in sorted(files):
            if not path.resolve().is_relative_to(source.resolve()):
                raise ValueError("Notice source escapes its crate")
            notices.append((str(path.relative_to(source)), path.read_bytes()))
        if package["name"] == "libsqlite3-sys":
            # The bundled SQLite amalgamation has its own public-domain notice,
            # distinct from the Rust wrapper's MIT license.
            header = source / "sqlite3/sqlite3.h"
            text = header.read_text()
            if (
                not text.startswith("/*")
                or "author disclaims copyright" not in text.split("*/", 1)[0]
            ):
                raise ValueError("Bundled SQLite declaration changed; review its notice")
            notices.append(
                ("sqlite3/sqlite3.h (opening notice)", (text.split("*/", 1)[0] + "*/\n").encode())
            )
        return notices
    # These crates omit a root license text from their published archive. The
    # existing notice pins their unmodified upstream source and matching MPL text.
    if (package["name"] == "uniffi" or package["name"].startswith("uniffi_")) and (
        package["version"] == "0.32.1"
        and package.get("license") == "MPL-2.0"
        and (package.get("repository") or "").rstrip("/") == "https://github.com/mozilla/uniffi-rs"
    ):
        return [
            (name, (root / NOTICES / name).read_bytes())
            for name in ["uniffi-mpl-2.0.txt", "uniffi-source.txt"]
        ]
    raise ValueError(f"No verified notice source for {package['name']} {package['version']}")


def generate(root=ROOT, metadata=None, full=None, normal=None):
    root = root.resolve()
    if metadata is None:
        metadata = json.loads(
            command(
                "cargo",
                "metadata",
                "--locked",
                "--offline",
                "--format-version",
                "1",
                "--filter-platform",
                TARGET,
                "--features",
                "reha-ffi/onnx",
            )
        )
    base = [
        "cargo",
        "tree",
        "--locked",
        "--offline",
        "-p",
        "reha-ffi",
        "--features",
        "onnx",
        "--target",
        TARGET,
        "--prefix",
        "none",
        "--format",
        "{p}|{f}",
    ]
    full = selected_tree(command(*base, "-e", "normal,build")) if full is None else full
    normal = (
        selected_tree(command(*base, "-e", "normal,no-proc-macro")) if normal is None else normal
    )
    if not set(normal) <= set(full):
        raise ValueError("Normal target dependencies escape the selected build closure")
    check_features(full)
    packages = defaultdict(list)
    for package in metadata["packages"]:
        packages[(package["name"], package["version"])].append(package)
    locks = tomllib.loads((root / "Cargo.lock").read_text())["package"]
    checksums = {(p["name"], p["version"], p.get("source")): p.get("checksum") for p in locks}
    notice_manifest = json.loads((root / NOTICES / "manifest.json").read_text())
    existing = {}
    for name, expected in notice_manifest.items():
        if name == COMBINED:
            continue
        data = (root / NOTICES / name).read_bytes()
        if sha(data) != expected:
            raise ValueError(f"Existing bundled notice changed: {name}")
        existing[expected] = name
    groups = {}
    records = []
    for key in sorted(full):
        if len(packages[key]) != 1:
            raise ValueError(f"Ambiguous or missing Cargo source identity: {key}")
        package = packages[key][0]
        source = package.get("source")
        checksum = checksums.get((*key, source))
        if source and not re.fullmatch(r"[0-9a-f]{64}", checksum or ""):
            raise ValueError(f"Unpinned external crate: {key}")
        record = {
            "name": key[0],
            "version": key[1],
            "source": source or "workspace",
            "checksum": checksum,
            "features": sorted(full[key]),
            "scope": "target_dependency" if key in normal else "build_dependency",
            "license_expression": package.get("license"),
            "repository": package.get("repository"),
            "notices": [],
        }
        if source:
            for name, data in notice_sources(package, root):
                digest = sha(data)
                notice = {"source_notice": name, "sha256": digest}
                if digest in existing:
                    notice["bundle_file"] = existing[digest]
                else:
                    notice.update({"bundle_file": COMBINED, "section": digest})
                    entry = groups.setdefault(
                        digest, {"text": data.decode("utf-8"), "users": set()}
                    )
                    entry["users"].add(f"{key[0]} {key[1]}: {name}")
                record["notices"].append(notice)
        records.append(record)
    parts = [
        "Rust dependency notices for the selected iOS normal/build closure.\n"
        "Generated by tooling/release/runtime_inventory.py; do not edit manually.\n"
        "Target dependencies and build-only tools are distinguished in runtime-inventory.json.\n"
        "Shared notice texts already bundled separately are referenced by that inventory.\n"
    ]
    for digest, entry in sorted(groups.items()):
        parts.append(
            f"\n{'=' * 72}\nNotice SHA-256: {digest}\n"
            + "\n".join(sorted(entry["users"]))
            + "\n\n"
            + entry["text"].rstrip()
            + "\n"
        )
    combined = "".join(parts).encode()
    notice_manifest[COMBINED] = sha(combined)
    inputs = [
        ".gitattributes",
        "Cargo.toml",
        "Cargo.lock",
        "packages/rust/reha-core/Cargo.toml",
        "packages/rust/reha-ffi/Cargo.toml",
        "apps/ios/project.yml",
        "packages/apple/AppleServices/Package.swift",
        "packages/apple/RehaCore/Package.swift",
        "packages/apple/VoiceActivity/Package.swift",
        "packages/apple/VoiceActivity/README.md",
        "packages/rust/reha-core/build.rs",
        "tooling/build/build-native.sh",
        "tooling/build/assemble-native.py",
        "tooling/build/verify-native-assets.py",
        "tooling/release/runtime_inventory.py",
        "tooling/release/runtime_policy.py",
        "config/toolchains/versions.json",
        "rust-toolchain.toml",
        "config/storage/workspace.json",
        "tooling/dev/workspace.py",
    ]
    locks = {}
    for name in ["small", "ios-runtime"]:
        path = f"ml/registry/runtime/{name}.lock.json"
        inputs.append(path)
        locks[name] = json.loads((root / path).read_text())
    # Keep vendored native code covered as well as its pinned upstream identity.
    inputs += [
        str(p.relative_to(root))
        for p in (root / "packages/apple/VoiceActivity/Sources").rglob("*")
        if p.is_file()
    ]
    inputs += [f"{NOTICES}/{name}" for name in notice_manifest if name != COMBINED]
    vad = (root / "packages/apple/VoiceActivity/README.md").read_text()
    inventory = {
        "schema_version": 1,
        "target": TARGET,
        "root_package": "reha-ffi",
        "features": ["onnx"],
        "selection": "cargo tree normal/build; procedural macros and their private dependencies are build scope",
        "source_inputs": {name: sha((root / name).read_bytes()) for name in sorted(set(inputs))},
        "rust_packages": records,
        "runtime_locks": locks,
        "native_components": [
            {
                "name": "libfvad/WebRTC VAD",
                "revision": re.search(r"Commit: `([a-f0-9]{40})`", vad)[1],
                "source_archive_sha256": re.search(r"Archive SHA-256: `([a-f0-9]{64})`", vad)[1],
                "notices": ["libfvad-LICENSE", "libfvad-AUTHORS", "libfvad-PATENTS"],
            },
        ],
        "system_components": {
            "provider": "Apple operating system",
            "bundled_by_app": False,
            "model_weight_identity": "not exposed; record observable OS per evaluation",
            "services": [
                "EventKit",
                "Speech",
                "FoundationModels",
                "AVFAudio",
                "AVSpeechSynthesizer",
            ],
        },
        "excluded_from_app": [
            "OCR training environments",
            "assistant training/export environments",
            "unqualified custom checkpoints",
            "host listening tools",
            "experimental Kokoro/Victoria weights, phonemizer and eSpeak-NG",
        ],
        "public_distribution_cleared": False,
        "open_distribution_items": [
            "first-party publisher/rights review",
        ],
        "generated_notice_sha256": sha(combined),
        "notice_manifest_sha256": sha(encoded(notice_manifest)),
    }
    return {
        f"{NOTICES}/{COMBINED}": combined,
        f"{NOTICES}/manifest.json": encoded(notice_manifest),
        INVENTORY: encoded(inventory),
    }


def verify(root=ROOT, bundle=None):
    data = json.loads((root / INVENTORY).read_text())
    if data.get("schema_version") != 1 or data.get("target") != TARGET:
        raise ValueError("Unknown runtime inventory schema or target")
    expected = {
        **data["source_inputs"],
        f"{NOTICES}/{COMBINED}": data["generated_notice_sha256"],
        f"{NOTICES}/manifest.json": data["notice_manifest_sha256"],
    }
    for name, digest in expected.items():
        path = root / name
        if (
            not path.resolve().is_relative_to(root.resolve())
            or not path.is_file()
            or sha(path.read_bytes()) != digest
        ):
            raise ValueError(f"Runtime inventory is stale: {name}; run make inventory-runtime")
    report = {
        "runtime_inventory_verified": True,
        "inventory_sha256": sha((root / INVENTORY).read_bytes()),
        "packages": len(data["rust_packages"]),
        "public_distribution_cleared": data["public_distribution_cleared"],
    }
    if bundle is not None:
        info = bundle / "Info.plist"
        if info.is_file() and plistlib.loads(info.read_bytes()).get("REHAExperimentalAssistant"):
            raise ValueError("Experimental assistant trials cannot use regular release packaging")
        if (bundle / "runtime-inventory.json").read_bytes() != (root / INVENTORY).read_bytes():
            raise ValueError("Bundled runtime inventory differs from reviewed source")
        notices = json.loads((root / NOTICES / "manifest.json").read_text())
        folder = bundle / "licenses"
        if {p.name for p in folder.iterdir()} != set(notices) | {"manifest.json"}:
            raise ValueError("Bundled notice files differ from reviewed source")
        for name in [*notices, "manifest.json"]:
            path = folder / name
            if (
                not path.resolve().is_relative_to(bundle.resolve())
                or path.read_bytes() != (root / NOTICES / name).read_bytes()
            ):
                raise ValueError(f"Bundled notice differs from reviewed source: {name}")
        report["bundled_notices_verified"] = len(notices)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["generate", "verify", "check"])
    parser.add_argument(
        "--bundle", type=Path, help="Verify inventory and notices inside a built app"
    )
    args = parser.parse_args()
    mode = args.mode
    if mode == "verify":
        print(json.dumps(verify(bundle=args.bundle)))
    else:
        outputs = generate()
        for name, content in outputs.items():
            path = ROOT / name
            if mode == "check":
                if not path.is_file() or path.read_bytes() != content:
                    raise ValueError(f"Generated runtime inventory differs: {name}")
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                temporary = path.with_suffix(path.suffix + ".part")
                temporary.write_bytes(content)
                temporary.replace(path)
        print(json.dumps(verify(bundle=args.bundle)))
