"""Locate original private evidence by its migrated workspace path, without copying it."""

import argparse
import hashlib
import json
from pathlib import Path

DEFAULT_ARCHIVE = Path.home() / "Documents/Project Archives/rehab-plan-ocr/2026-09-26"


def locate(archive, name, expected_sha256=None):
    relative = Path(name.removeprefix("archive:workspace/"))
    if relative.is_absolute() or ".." in relative.parts or str(relative) in {"", "."}:
        raise ValueError("Provide a relative migrated workspace path")
    archive = archive.resolve(strict=True)
    receipt = json.loads((archive / "recovery.json").read_text())
    mapping = json.loads((archive / receipt["path_map"]).read_text())
    matches = [old for old, new in mapping.items() if new == relative.as_posix()]
    if len(matches) != 1:
        raise ValueError("The archived path is absent or ambiguous")
    workspace = (archive / receipt["workspace"]).resolve(strict=True)
    original = (workspace / matches[0]).resolve(strict=True)
    if not original.is_relative_to(workspace):
        raise ValueError("An archived symlink points outside the retained workspace")
    if expected_sha256 is not None:
        with original.open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
        if actual != expected_sha256:
            raise ValueError("Original evidence does not match the requested SHA-256")
    return original


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path")
    parser.add_argument("--archive", type=Path, default=DEFAULT_ARCHIVE)
    parser.add_argument("--sha256")
    args = parser.parse_args()
    print(locate(args.archive, args.path, args.sha256))


if __name__ == "__main__":
    main()
