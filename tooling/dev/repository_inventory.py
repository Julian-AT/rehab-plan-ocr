"""Account for every versioned file; ownership coverage is not a source-code audit."""

import argparse
import hashlib
import json
from pathlib import Path

import source_tree

ROOT = Path(__file__).resolve().parents[2]
# Prefixes are disjoint. Root files are named explicitly so new unexplained files fail.
GROUPS = [
    (
        "workspace",
        [
            "AGENTS.md",
            "CLAUDE.md",
            "Makefile",
            "LICENSE",
            ".editorconfig",
            "README.md",
            "Cargo.toml",
            "Cargo.lock",
            "rust-toolchain.toml",
            "pyproject.toml",
            "uv.lock",
            ".gitattributes",
            ".gitignore",
            ".python-version",
            ".swift-format",
        ],
        "development",
        "Build, tools, policy and entry documentation",
        ["make", "Cargo workspace", "uv", "Swift formatter", "Git"],
        "retain",
    ),
    (
        "ci",
        [".github/"],
        "development",
        "Hosted verification and evidence retention",
        ["GitHub Actions"],
        "retain; complete hosted run externally blocked",
    ),
    (
        "configuration",
        ["config/"],
        "development",
        "Pinned tools, simulators and storage rules",
        ["tooling/dev/quality.py", "ml/evaluation/device/simulator.py", "tooling/dev/artifacts.py"],
        "retain",
    ),
    (
        "ios",
        ["apps/ios/"],
        "product-and-tests",
        "App, extensions, Xcode specifications and native probes",
        [
            "apps/ios/project.yml",
            "apps/ios/IntegrationTests/project.yml",
            "tooling/checks/test-*.sh",
        ],
        "retain; Xcode recursive sources, extension entry points and standalone probes",
    ),
    (
        "rust",
        ["packages/rust/"],
        "product-and-tests",
        "Domain, persistence, parser, CLI and UniFFI exports",
        ["Cargo.toml", "tooling/build/build-native.sh", "make test"],
        "retain; exports/test discovery cannot be inferred from Swift text searches",
    ),
    (
        "apple-services",
        ["packages/apple/AppleServices/"],
        "product",
        "EventKit, storage and platform effects",
        ["apps/ios/project.yml", "apps/ios/IntegrationTests/project.yml"],
        "retain",
    ),
    (
        "bindings",
        ["packages/apple/RehaCore/"],
        "generated-product",
        "UniFFI bindings, headers and package",
        ["tooling/build/build-native.sh bindings", "make check-bindings"],
        "retain; generator owns bindings",
    ),
    (
        "vad",
        ["packages/apple/VoiceActivity/"],
        "third-party-product",
        "Vendored pinned VAD with source notices",
        [
            "apps/ios/project.yml",
            "tooling/checks/test-vad.sh",
            "tooling/release/runtime_inventory.py",
        ],
        "retain",
    ),
    (
        "assistant-runtime",
        ["packages/apple/LocalAssistant/"],
        "experiment",
        "Isolated native assistant bridge",
        ["apps/ios/assistant-trial.yml", "tooling/build/build-assistant-native.py"],
        "retain; failed model evidence",
    ),
    (
        "data-tools",
        ["ml/data/"],
        "development",
        "Consent intake, annotation, augmentation and synthesis",
        ["Makefile", "tooling/dev/quality.py test-tools"],
        "retain; human approval remains required",
    ),
    (
        "evaluation",
        ["ml/evaluation/"],
        "development-evidence",
        "Recognition, conversation, audio and device evaluation",
        ["Makefile", "tooling/checks", "tooling/dev/quality.py test-tools"],
        "retain; separate contracts and fixtures",
    ),
    (
        "experiments",
        ["ml/experiments/"],
        "development-evidence",
        "Dated model evidence and bounded research runners",
        ["ml/experiments/vlm/README.md", "tooling/dev/probes.py", "ml/registry"],
        "retain; VLM consumed by region comparison, Swift probes have explicit Make entries",
    ),
    (
        "models",
        ["ml/registry/", "ml/training/", "ml/README.md"],
        "development-and-runtime-pins",
        "Model identities, locked training/export and runtime manifests",
        [
            "Makefile",
            "LICENSE",
            ".editorconfig",
            "tooling/build/verify-native-assets.py",
            "tooling/release/runtime_inventory.py",
        ],
        "retain; selected and resumable artifacts stay private",
    ),
    (
        "tooling",
        ["tooling/"],
        "development",
        "Setup, checks, builds, packaging and automatically found tests",
        ["Makefile", ".github/workflows/verify.yml", "tooling/dev/quality.py test-tools"],
        "retain",
    ),
    (
        "visual-evidence",
        ["docs/product/visual-baseline/", "docs/device/", "docs/decisions/"],
        "protected-evidence",
        "Chosen visual references, original device capture and palette decision",
        [
            "tooling/checks/compare-visual-suite.py",
            "tooling/checks/tests/test-documentation.py",
            "docs/releases/history/kokoro-device-update.md",
        ],
        "retain unchanged; device capture is distinct evidence",
    ),
    (
        "documentation",
        [
            "docs/README.md",
            "docs/architecture/",
            "docs/development/",
            "docs/releases/",
            "docs/product/branding/",
            "docs/product/research/",
            "docs/product/privacy.md",
            "docs/product/support.md",
        ],
        "documentation-and-evidence",
        "Current instructions and dated historical evidence",
        ["README.md", "docs/README.md", "tooling/checks/tests/test-documentation.py"],
        "retain; historical reports are immutable, current claims require live-code verification",
    ),
    (
        "notices",
        ["docs/third-party/"],
        "third-party-product",
        "Exact runtime notices, dependency closure and retained experimental notices",
        [
            "apps/ios/project.yml",
            "tooling/release/runtime_inventory.py",
            "tooling/release/bundle.py",
        ],
        "retain; release excludes eSpeak, experimental provenance is outside app resources",
    ),
]


def classify(name):
    matches = [
        g for g in GROUPS if any(name.startswith(p) if p.endswith("/") else name == p for p in g[1])
    ]
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one documented owner for {name}; got {len(matches)}")
    return matches[0]


def inventory(root=ROOT):
    names = source_tree.names(root)
    groups = {
        g[0]: {
            "kind": g[2],
            "purpose": g[3],
            "consumers": g[4],
            "decision": g[5],
            "content_review": "not-completed-by-this-inventory",
            "files": [],
        }
        for g in GROUPS
    }
    for name in sorted(set(filter(None, names))):
        group = classify(name)[0]
        path = root / name
        if not path.is_file() or path.is_symlink():
            raise ValueError(f"Tracked file missing or unexpected link: {name}")
        content = path.read_bytes()
        groups[group]["files"].append(
            {"path": name, "bytes": len(content), "sha256": hashlib.sha256(content).hexdigest()}
        )
    return {
        "schema_version": 1,
        "scope": "ownership-and-consumers-not-complete-code-review",
        "files": sum(len(g["files"]) for g in groups.values()),
        "groups": groups,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    value = inventory()
    if args.output:
        path = args.output.resolve()
        if not path.is_relative_to(ROOT / ".local/maintenance"):
            raise ValueError("Working inventory belongs below .local/maintenance")
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("x") as stream:
            json.dump(value, stream, indent=2)
            stream.write("\n")
    print(
        f"Accounted for {value['files']} files in {len(value['groups'])} consumer groups; content audit remains open."
    )


if __name__ == "__main__":
    main()
