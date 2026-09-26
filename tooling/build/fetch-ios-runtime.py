# /// script
# requires-python = ">=3.11"
# dependencies = ["certifi==2026.1.4"]
# ///
"""Install the pinned official ONNX Runtime static iOS libraries for Rust linking."""

import hashlib
import io
import json
import os
import ssl
import subprocess
import tempfile
import urllib.request
import zipfile
from pathlib import Path

import certifi

ROOT = Path(__file__).resolve().parents[2]


def matches(path, expected):
    if not path.is_file() or path.stat().st_size != expected["bytes"]:
        return False
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest() == expected["sha256"]


def atomic_bytes(path, data):
    descriptor, name = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}-")
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def restore(project):
    lock_path = project / "ml/registry/runtime/ios-runtime.lock.json"
    lock = json.loads(lock_path.read_text())
    if not lock.get("sha256") or not lock.get("bytes"):
        raise SystemExit("iOS runtime needs a committed checksum and size before restoration")
    root = project / ".local/models/runtime/runtime"
    root.mkdir(parents=True, exist_ok=True)
    cache = root / "onnxruntime-1.22.0.zip"
    if matches(cache, lock):
        data = cache.read_bytes()
    else:
        with urllib.request.urlopen(
            lock["url"], timeout=120, context=ssl.create_default_context(cafile=certifi.where())
        ) as response:
            data = response.read(lock["bytes"] + 1)
    if lock["sha256"] != hashlib.sha256(data).hexdigest() or lock["bytes"] != len(data):
        raise SystemExit("iOS runtime checksum mismatch")
    if not matches(cache, lock):
        atomic_bytes(cache, data)
    # Both architectures must pass before either installation is replaced. Extraction
    # never writes to a live linker input; interruption leaves the previous files intact.
    with tempfile.TemporaryDirectory(prefix=".restore-", dir=root) as temporary:
        staging = Path(temporary)
        candidates = []
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            license_text = archive.read("LICENSE")
            for target, folder in [
                ("aarch64-apple-ios", "ios-arm64"),
                ("aarch64-apple-ios-sim", "ios-arm64_x86_64-simulator"),
            ]:
                output = root / target / "libonnxruntime.a"
                expected = lock["libraries"][target]
                if matches(output, expected):
                    print(f"Verified static ORT {lock['version']} for {target}")
                    continue
                universal = staging / f"{target}-universal.a"
                universal.write_bytes(
                    archive.read(
                        f"onnxruntime.xcframework/{folder}/onnxruntime.framework/onnxruntime"
                    )
                )
                candidate = staging / f"{target}.a"
                subprocess.run(
                    ["xcrun", "lipo", str(universal), "-thin", "arm64", "-output", str(candidate)],
                    check=True,
                )
                universal.unlink()
                if not matches(candidate, expected):
                    raise SystemExit(
                        f"Extracted runtime differs from the committed architecture pin: {target}"
                    )
                with candidate.open("rb") as stream:
                    os.fsync(stream.fileno())
                candidates.append((candidate, output))
        for candidate, output in candidates:
            output.parent.mkdir(parents=True, exist_ok=True)
            candidate.replace(output)
            print(f"Installed static ORT {lock['version']} for {output.parent.name}")
        license_path = root / "LICENSE"
        if not license_path.is_file() or license_path.read_bytes() != license_text:
            atomic_bytes(license_path, license_text)


if __name__ == "__main__":
    restore(ROOT)
