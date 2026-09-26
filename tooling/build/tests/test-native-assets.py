"""Builds must reject stale assets while leaving valid offline setup untouched."""

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).parents[1] / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


assets = load("verify-native-assets")
phonemizer = load("build-phonemizer")


def pin(path, content=b"synthetic artifact"):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)
    return {"bytes": len(content), "sha256": hashlib.sha256(content).hexdigest()}


class OfflineAssetTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        registry = self.root / "ml/registry/runtime"
        registry.mkdir(parents=True)
        for name in ["small"]:
            root = self.root / ".local/models/runtime" / name
            entry = pin(root / "model.bin") | {"path": "model.bin"}
            manifest = {"files": [entry], "bundle_directory": name}
            if name == "small":
                manifest["dictionary_sha256"] = pin(root / "dictionary.json", b'["a"]')["sha256"]
            data = json.dumps(manifest)
            (registry / f"{name}.lock.json").write_text(data)
            (root / "manifest.json").write_text(data)
        self.library = (
            self.root / ".local/models/runtime/runtime/aarch64-apple-ios-sim/libonnxruntime.a"
        )
        runtime = {"libraries": {"aarch64-apple-ios-sim": pin(self.library)}}
        (registry / "ios-runtime.lock.json").write_text(json.dumps(runtime))
        notices = self.root / "docs/third-party/licenses"
        notice = pin(notices / "NOTICE")["sha256"]
        (notices / "manifest.json").write_text(json.dumps({"NOTICE": notice}))

    def verify(self):
        assets.verify(self.root, ["aarch64-apple-ios-sim"])

    def snapshot(self):
        return {
            str(p.relative_to(self.root)): (p.read_bytes(), p.stat().st_mtime_ns)
            for p in self.root.rglob("*")
            if p.is_file()
        }

    def test_target_verification_neither_requires_device_slice_nor_writes_files(self):
        before = self.snapshot()
        self.verify()
        self.assertEqual(self.snapshot(), before)

    def test_missing_or_corrupt_library_is_not_repaired_by_a_build(self):
        self.library.write_bytes(b"corrupt")
        with self.assertRaisesRegex(ValueError, "Missing or corrupt"):
            self.verify()
        self.assertEqual(self.library.read_bytes(), b"corrupt")
        self.library.unlink()
        with self.assertRaises(ValueError):
            self.verify()
        self.assertFalse(self.library.exists())

    def test_dictionary_and_manifest_changes_are_rejected(self):
        dictionary = self.root / ".local/models/runtime/small/dictionary.json"
        dictionary.write_text('["b"]')
        with self.assertRaisesRegex(ValueError, "dictionary"):
            self.verify()
        dictionary.write_text('["a"]')
        (dictionary.parent / "manifest.json").write_text("{}")
        with self.assertRaisesRegex(ValueError, "manifest"):
            self.verify()


class PhonemizerCacheTests(unittest.TestCase):
    def test_cache_binds_source_toolchain_architecture_and_actual_library(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            pin(source / "code.c", b"source version one")
            expected = phonemizer.identity(source, "simulator", ["option"], "toolchain one")
            build = root / "build"
            name = "src/libespeak-ng/libespeak-ng.a"
            entry = pin(build / name)
            (build / "build-identity.json").write_text(
                json.dumps({"identity": expected, "artifacts": {name: entry["sha256"]}})
            )
            self.assertTrue(phonemizer.cache_matches(build, expected))
            for field in ["toolchain", "variant", "builder_sha256"]:
                with self.subTest(field=field):
                    self.assertFalse(phonemizer.cache_matches(build, expected | {field: "changed"}))
            (source / "code.c").write_text("source version two")
            changed = phonemizer.identity(source, "simulator", ["option"], "toolchain one")
            self.assertFalse(phonemizer.cache_matches(build, changed))
            (build / name).write_text("corrupt")
            self.assertFalse(phonemizer.cache_matches(build, expected))


if __name__ == "__main__":
    unittest.main()
