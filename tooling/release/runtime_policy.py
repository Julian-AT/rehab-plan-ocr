"""Mechanical release exclusions; these checks do not grant distribution rights."""

import json
import re

MODELS = ("small",)
EXCLUDED_RESOURCE_PARTS = {
    "kokoro-german",
    "espeak-ng-data",
    "kikiri-victoria-source",
    "libespeak-ng.a",
    "libucd.a",
}
EXCLUDED_ASSISTANT_PARTS = {"assistant-trial", "assistant-system-v1.txt"}
ASSISTANT_MANIFEST_KEYS = {"model_sha256", "prompt_sha256", "native_identity"}
ESPEAK_SYMBOL = re.compile(rb"(?:^|[^a-zA-Z0-9])_?espeak(?:_ng)?_[a-zA-Z0-9]+")
# mach-o/loader.h and mach-o/fat.h: both byte orders and 32-/64-bit headers.
MACHO_MAGICS = {
    0xFEEDFACE,
    0xCEFAEDFE,
    0xFEEDFACF,
    0xCFFAEDFE,
    0xCAFEBABE,
    0xBEBAFECA,
    0xCAFEBABF,
    0xBFBAFECA,
}


def check_features(selected):
    for (name, _), features in selected.items():
        if name in {"reha-core", "reha-ffi"} and "kokoro" in features:
            raise ValueError("Experimental Kokoro feature is forbidden in the release closure")


def check_symbols(data):
    if ESPEAK_SYMBOL.search(data):
        raise ValueError("Experimental eSpeak symbols are forbidden in release binaries")


def check_binary(path):
    # Stream the final executable/archives too: renamed resources or stale archive
    # caches must not silently evade the dependency and resource checks. This is
    # supplementary to the selected Cargo feature closure, not a license audit.
    previous = b""
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            check_symbols(previous + chunk)
            previous = chunk[-128:]


def embedded_code(app):
    """Find code by its header, including renamed libraries and Debug dylibs."""
    for path in sorted(app.rglob("*")):
        if not path.is_file():
            continue
        with path.open("rb") as source:
            header = source.read(8)
        if header == b"!<arch>\n" or int.from_bytes(header[:4], "big") in MACHO_MAGICS:
            yield path


def check_resources(app):
    for path in app.rglob("*"):
        parts = {part.lower() for part in path.relative_to(app).parts}
        if parts & EXCLUDED_RESOURCE_PARTS:
            raise ValueError("Experimental speech resources are forbidden in release bundles")
        if parts & EXCLUDED_ASSISTANT_PARTS:
            raise ValueError("Experimental assistant resources are forbidden in release bundles")
        if not path.is_file():
            continue
        with path.open("rb") as source:
            header = source.read(4)
        # Inspect content as well as names: a renamed model or a missing trial
        # Info.plist marker must not turn development weights into release assets.
        if path.suffix.lower() == ".gguf" or header == b"GGUF":
            raise ValueError("Custom assistant models are forbidden in release bundles")
        if path.name.lower() == "manifest.json":
            try:
                manifest = json.loads(path.read_bytes())
            except (ValueError, UnicodeError):
                continue
            # A qualification flag is not release approval. Match the trial
            # artifact identity even after its containing directory was renamed.
            if isinstance(manifest, dict) and ASSISTANT_MANIFEST_KEYS <= manifest.keys():
                raise ValueError("Custom assistant manifests are forbidden in release bundles")
