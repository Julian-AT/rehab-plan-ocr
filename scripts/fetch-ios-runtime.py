# /// script
# requires-python = ">=3.11"
# dependencies = ["certifi==2026.1.4"]
# ///
"""Install the pinned official ONNX Runtime static iOS libraries for Rust linking."""

import hashlib
import io
import json
import ssl
import subprocess
import urllib.request
import zipfile
from pathlib import Path

import certifi

ROOT = Path(__file__).resolve().parents[1]
URL = "https://download.onnxruntime.ai/pod-archive-onnxruntime-c-1.22.0.zip"
lock_path = ROOT / "models/ios-runtime.lock.json"
lock = json.loads(lock_path.read_text())
if not lock.get("sha256") or not lock.get("bytes"):
    raise SystemExit("iOS runtime needs a committed checksum and size before restoration")
root = ROOT / "models/private/runtime"
root.mkdir(parents=True, exist_ok=True)
cache = root / "onnxruntime-1.22.0.zip"
if cache.exists() and lock.get("sha256") == hashlib.sha256(cache.read_bytes()).hexdigest():
    data = cache.read_bytes()
else:
    with urllib.request.urlopen(
        lock["url"],
        timeout=120,
        context=ssl.create_default_context(cafile=certifi.where()),
    ) as response:
        data = response.read()
digest = hashlib.sha256(data).hexdigest()
if lock["sha256"] != digest or lock["bytes"] != len(data):
    raise SystemExit("iOS runtime checksum mismatch")
cache.write_bytes(data)
with zipfile.ZipFile(io.BytesIO(data)) as archive:
    for target, folder in [
        ("aarch64-apple-ios", "ios-arm64"),
        ("aarch64-apple-ios-sim", "ios-arm64_x86_64-simulator"),
    ]:
        output = root / target
        output.mkdir(parents=True, exist_ok=True)
        binary = archive.read(f"onnxruntime.xcframework/{folder}/onnxruntime.framework/onnxruntime")
        universal = output / "universal.a"
        universal.write_bytes(binary)
        subprocess.run(
            [
                "xcrun",
                "lipo",
                str(universal),
                "-thin",
                "arm64",
                "-output",
                str(output / "libonnxruntime.a"),
            ],
            check=True,
        )
        universal.unlink()
        print(f"Installed static ORT {lock['version']} for {target}: {len(binary)} bytes")
    (root / "LICENSE").write_bytes(archive.read("LICENSE"))
