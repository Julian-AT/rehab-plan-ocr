"""Pinned personal-device Victoria inventory, separate from public release policy."""

import hashlib
import json

SOURCES = (
    "apps/ios/private-victoria.yml",
    "apps/ios/Features/Conversation/VictoriaSpeech.swift",
    "apps/ios/Features/Conversation/SpeechOutput.swift",
    "apps/ios/Features/Conversation/SystemSpeech.swift",
    "tooling/build/build-private-victoria.py",
    "tooling/build/build-phonemizer.py",
    "tooling/release/private_speech.py",
    "packages/rust/reha-core/src/speech.rs",
    "packages/rust/reha-core/build.rs",
    "packages/rust/reha-ffi/src/speech.rs",
    "ml/registry/runtime/kokoro.lock.json",
)
NOTICES = "docs/third-party/experiments/kokoro"


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify(app, root, model_bundle):
    folder = app / "private-speech"
    manifest = json.loads((folder / "manifest.json").read_text())
    if (
        manifest.get("profile") != "personal-victoria"
        or manifest.get("public_distribution") is not False
    ):
        raise ValueError("Expected explicitly personal Victoria provenance")
    if manifest.get("cargo_features") != ["kokoro"]:
        raise ValueError("Unexpected private speech feature closure")
    expected = {name: sha(root / name) for name in SOURCES}
    if manifest.get("sources") != expected:
        raise ValueError("Private speech sources differ from the compiled profile")
    if manifest.get("base_inventory_sha256") != sha(
        root / "docs/third-party/runtime-inventory.json"
    ):
        raise ValueError("Private speech base dependency inventory changed")
    notices = json.loads((root / NOTICES / "manifest.json").read_text())
    if set(p.name for p in folder.iterdir()) != set(notices) | {"manifest.json"}:
        raise ValueError("Private voice notices differ from the pinned set")
    for name, digest in notices.items():
        if sha(folder / name) != digest or sha(root / NOTICES / name) != digest:
            raise ValueError("Private voice notice differs from pinned bytes")
    # Native identities include source patches, compiler, target, flags and hashes
    # of both static libraries. This profile does not claim public distribution.
    expected_targets = {"aarch64-apple-ios", "aarch64-apple-ios-sim"}
    if set(manifest.get("phonemizer", {})) != expected_targets:
        raise ValueError("Missing private phonemizer target provenance")
    for target, record in manifest["phonemizer"].items():
        base = root / ".local/builds/phonemizer" / target
        if json.loads((base / "build-identity.json").read_text()) != record:
            raise ValueError("Private phonemizer provenance changed")
        for name, digest in record["artifacts"].items():
            path = base / name
            if not path.resolve().is_relative_to(base.resolve()) or sha(path) != digest:
                raise ValueError("Private phonemizer library differs from its build receipt")
    lock = json.loads((root / "ml/registry/runtime/kokoro.lock.json").read_text())
    model = model_bundle(app / "kokoro-german", lock, strict=True)
    return {
        "provider": "local Victoria/Kokoro",
        "voice": "victoria",
        "bundled_model_files": model["pinned_files"],
        "model": model,
        "private_inventory_sha256": sha(folder / "manifest.json"),
        "public_distribution": False,
        "experimental_speech_excluded": False,
        "device_voice_acceptance": "pending",
    }
