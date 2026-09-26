"""Interrupted restoration cannot damage live native linker inputs."""

import hashlib
import importlib.util
import io
import json
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "ios_runtime_restoration", Path(__file__).resolve().parents[1] / "fetch-ios-runtime.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def pin(data):
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


class RuntimeRestorationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.assets = self.root / ".local/models/runtime/runtime"
        self.assets.mkdir(parents=True)
        self.archives = {
            "aarch64-apple-ios": b"synthetic device archive",
            "aarch64-apple-ios-sim": b"synthetic simulator archive",
        }
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as archive:
            for target, folder in [
                ("aarch64-apple-ios", "ios-arm64"),
                ("aarch64-apple-ios-sim", "ios-arm64_x86_64-simulator"),
            ]:
                archive.writestr(
                    f"onnxruntime.xcframework/{folder}/onnxruntime.framework/onnxruntime",
                    self.archives[target],
                )
            archive.writestr("LICENSE", "Synthetic test license")
        self.download = data.getvalue()
        self.cache = self.assets / "onnxruntime-1.22.0.zip"
        self.cache.write_bytes(self.download)
        self.lock = self.root / "ml/registry/runtime/ios-runtime.lock.json"
        self.lock.parent.mkdir(parents=True)
        self.lock.write_text(
            json.dumps(
                pin(self.download)
                | {
                    "url": "https://invalid.example/synthetic.zip",
                    "version": "synthetic",
                    "libraries": {target: pin(data) for target, data in self.archives.items()},
                }
            )
        )
        self.inputs = {}
        for target in self.archives:
            path = self.assets / target / "libonnxruntime.a"
            path.parent.mkdir(parents=True)
            path.write_bytes(b"previous installation")
            self.inputs[path] = (path.read_bytes(), path.stat().st_mtime_ns)
        self.lock_before = (self.lock.read_bytes(), self.lock.stat().st_mtime_ns)

    def thin(self, command, *, check):
        self.assertTrue(check)
        self.assertNotIn(Path(command[-1]), self.inputs)
        Path(command[-1]).write_bytes(Path(command[2]).read_bytes())

    def restore(self, thin=None):
        with (
            patch.object(MODULE.subprocess, "run", side_effect=thin or self.thin),
            patch.object(MODULE.urllib.request, "urlopen", side_effect=AssertionError("network")),
        ):
            MODULE.restore(self.root)

    def assert_preserved(self):
        for path, expected in self.inputs.items():
            self.assertEqual((path.read_bytes(), path.stat().st_mtime_ns), expected)
        self.assertEqual((self.lock.read_bytes(), self.lock.stat().st_mtime_ns), self.lock_before)
        self.assertFalse(list(self.assets.glob(".restore-*")))

    def test_failed_second_architecture_preserves_both_live_inputs_and_restarts_offline(self):
        calls = 0

        def fail(command, *, check):
            nonlocal calls
            calls += 1
            self.thin(command, check=check)
            if calls == 2:
                raise subprocess.CalledProcessError(1, command)

        with self.assertRaises(subprocess.CalledProcessError):
            self.restore(fail)
        self.assert_preserved()
        self.restore()
        for target, expected in self.archives.items():
            self.assertEqual((self.assets / target / "libonnxruntime.a").read_bytes(), expected)

    def test_interruption_after_partial_write_preserves_live_inputs(self):
        def interrupt(command, *, check):
            Path(command[-1]).write_bytes(b"incomplete extraction")
            raise KeyboardInterrupt

        with self.assertRaises(KeyboardInterrupt):
            self.restore(interrupt)
        self.assert_preserved()

    def test_invalid_extracted_checksum_never_publishes(self):
        def corrupt(command, *, check):
            Path(command[-1]).write_bytes(b"incorrect archive")

        with self.assertRaisesRegex(SystemExit, "architecture pin"):
            self.restore(corrupt)
        self.assert_preserved()

    def test_verified_offline_repeat_preserves_all_timestamps_and_needs_no_extractor(self):
        self.restore()
        paths = [*self.inputs, self.cache, self.assets / "LICENSE", self.lock]
        before = {path: (path.read_bytes(), path.stat().st_mtime_ns) for path in paths}
        with (
            patch.object(MODULE.subprocess, "run", side_effect=AssertionError("extractor")),
            patch.object(MODULE.urllib.request, "urlopen", side_effect=AssertionError("network")),
        ):
            MODULE.restore(self.root)
        self.assertEqual(
            {path: (path.read_bytes(), path.stat().st_mtime_ns) for path in paths}, before
        )

    def test_corrupt_download_leaves_existing_cache_and_installations_unchanged(self):
        self.cache.write_bytes(b"previous interrupted download")
        before = self.cache.read_bytes()
        with patch.object(MODULE.urllib.request, "urlopen", return_value=io.BytesIO(b"corrupt")):
            with self.assertRaisesRegex(SystemExit, "checksum mismatch"):
                MODULE.restore(self.root)
        self.assertEqual(self.cache.read_bytes(), before)
        self.assert_preserved()


if __name__ == "__main__":
    unittest.main()
