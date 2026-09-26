"""Mechanical release exclusions; these checks do not grant distribution rights."""

import re

MODELS = ("small",)
EXCLUDED_RESOURCE_PARTS = {
    "kokoro-german",
    "espeak-ng-data",
    "kikiri-victoria-source",
    "libespeak-ng.a",
    "libucd.a",
}
ESPEAK_SYMBOL = re.compile(rb"(?:^|[^a-zA-Z0-9])_?espeak(?:_ng)?_[a-zA-Z0-9]+")


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


def check_resources(app):
    for path in app.rglob("*"):
        if any(part.lower() in EXCLUDED_RESOURCE_PARTS for part in path.relative_to(app).parts):
            raise ValueError("Experimental speech resources are forbidden in release bundles")
