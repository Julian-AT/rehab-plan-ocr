"""Reject stale or incomplete runtime notices without private data or a Cargo registry."""

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tooling/release"))
import runtime_inventory as inventory  # noqa: E402


class InventoryTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / "repository"
        # Only public pinned source inputs, never local model or patient assets.
        current = json.loads((ROOT / inventory.INVENTORY).read_text())
        for name in [*current["source_inputs"], f"{inventory.NOTICES}/manifest.json"]:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        self.metadata = {"packages": []}
        self.full = {}
        self.normal = {}
        self.locked = []
        self.package("app", source=None)
        self.package("selected", normal=True)
        self.package("compiler-tool", normal=False)
        self.package("inactive-optional", selected=False)
        (self.root / "Cargo.lock").write_text("\n".join(self.locked))

    def package(self, name, normal=True, selected=True, source="registry+synthetic"):
        path = self.root / "fixture-crates" / name
        path.mkdir(parents=True)
        (path / "Cargo.toml").write_text("# Synthetic fixture\n")
        (path / "LICENSE").write_text("Synthetic shared license for inventory tests.\n")
        self.metadata["packages"].append(
            {
                "name": name,
                "version": "1.0.0",
                "source": source,
                "license": "MIT",
                "repository": None,
                "manifest_path": str(path / "Cargo.toml"),
            }
        )
        self.locked.append(
            f'[[package]]\nname = "{name}"\nversion = "1.0.0"\n'
            + (f'source = "{source}"\nchecksum = "{"a" * 64}"\n' if source else "")
        )
        if selected:
            self.full[(name, "1.0.0")] = {"selected-feature"}
            if normal:
                self.normal[(name, "1.0.0")] = {"selected-feature"}

    def generate(self):
        with patch.object(
            inventory, "command", side_effect=AssertionError("Unexpected Cargo call")
        ):
            outputs = inventory.generate(self.root, self.metadata, self.full, self.normal)
        for name, content in outputs.items():
            (self.root / name).write_bytes(content)
        return outputs

    def bundle(self):
        self.generate()
        bundle = self.root / "Synthetic.app"
        shutil.copytree(self.root / inventory.NOTICES, bundle / "licenses")
        shutil.copyfile(self.root / inventory.INVENTORY, bundle / "runtime-inventory.json")
        return bundle

    def test_actual_closure_excludes_optional_metadata_and_deduplicates_notices(self):
        outputs = self.generate()
        data = json.loads(outputs[inventory.INVENTORY])
        packages = {p["name"]: p for p in data["rust_packages"]}
        self.assertEqual(set(packages), {"app", "selected", "compiler-tool"})
        self.assertEqual(packages["selected"]["scope"], "target_dependency")
        self.assertEqual(packages["compiler-tool"]["scope"], "build_dependency")
        self.assertEqual(packages["selected"]["features"], ["selected-feature"])
        combined = outputs[f"{inventory.NOTICES}/{inventory.COMBINED}"]
        self.assertEqual(combined.count(b"Synthetic shared license"), 1)
        self.assertEqual(outputs, self.generate())

    def test_cargo_tree_repeat_features_and_invalid_output(self):
        tree = inventory.selected_tree("a v1.0.0|std\na v1.0.0|std,ffi (*)\nb v2.0.0 (/path)|\n")
        self.assertEqual(tree, {("a", "1.0.0"): {"std", "ffi"}, ("b", "2.0.0"): set()})
        for value in ["", "warning: unexpected tool output", "a v1.0.0"]:
            with self.assertRaises(ValueError):
                inventory.selected_tree(value)

    def test_changed_or_missing_notice_source_rejects_generation(self):
        notice = self.root / "fixture-crates/selected/LICENSE"
        notice.unlink()
        with self.assertRaisesRegex(ValueError, "No verified notice source"):
            self.generate()
        notice.write_text("Synthetic replacement\n")
        (self.root / inventory.NOTICES / "uniffi-mpl-2.0.txt").write_text("Altered notice")
        with self.assertRaisesRegex(ValueError, "Existing bundled notice changed"):
            self.generate()

    def test_source_notice_cannot_escape_crate(self):
        notice = self.root / "fixture-crates/selected/LICENSE"
        notice.unlink()
        notice.symlink_to(self.root / "Cargo.lock")
        with self.assertRaisesRegex(ValueError, "escapes its crate"):
            self.generate()

    def test_verification_is_read_only_and_rejects_stale_source(self):
        self.generate()
        before = {
            p: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.root.rglob("*") if p.is_file()
        }
        with patch.object(
            inventory, "command", side_effect=AssertionError("Unexpected Cargo call")
        ):
            self.assertEqual(inventory.verify(self.root)["packages"], 3)
        after = {
            p: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.root.rglob("*") if p.is_file()
        }
        self.assertEqual(before, after)
        (self.root / "Cargo.lock").write_text("Changed dependency")
        with self.assertRaisesRegex(ValueError, "Runtime inventory is stale: Cargo.lock"):
            inventory.verify(self.root)

    def test_inventory_input_cannot_escape_repository(self):
        self.generate()
        path = self.root / inventory.INVENTORY
        data = json.loads(path.read_text())
        outside = self.root.parent / "outside.txt"
        outside.write_text("outside")
        data["source_inputs"]["../outside.txt"] = inventory.sha(outside.read_bytes())
        path.write_bytes(inventory.encoded(data))
        with self.assertRaisesRegex(ValueError, "Runtime inventory is stale"):
            inventory.verify(self.root)

    def test_bundle_rejects_missing_extra_or_changed_notices(self):
        bundle = self.bundle()
        self.assertGreater(inventory.verify(self.root, bundle)["bundled_notices_verified"], 1)
        notice = bundle / "licenses" / inventory.COMBINED
        original = notice.read_bytes()
        notice.write_text("Altered bundled license")
        with self.assertRaisesRegex(ValueError, "Bundled notice differs"):
            inventory.verify(self.root, bundle)
        notice.unlink()
        with self.assertRaisesRegex(ValueError, "Bundled notice files differ"):
            inventory.verify(self.root, bundle)
        notice.write_bytes(original)
        (bundle / "licenses/extra.txt").write_text("Unreviewed notice")
        with self.assertRaisesRegex(ValueError, "Bundled notice files differ"):
            inventory.verify(self.root, bundle)

    def test_bundle_rejects_old_inventory(self):
        bundle = self.bundle()
        (bundle / "runtime-inventory.json").write_text("{}")
        with self.assertRaisesRegex(ValueError, "Bundled runtime inventory differs"):
            inventory.verify(self.root, bundle)


if __name__ == "__main__":
    unittest.main()
