import importlib.util
import json
import os
import random
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

spec = importlib.util.spec_from_file_location(
    "artifacts", os.environ.get("ARTIFACTS_TEST_MODULE", Path(__file__).parents[1] / "artifacts.py")
)
artifacts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artifacts)


class ReferenceFilterTests(unittest.TestCase):
    def test_lexical_boundaries_match_pathlib_without_resolving(self):
        cases = [
            ("a/b", "a", True),
            ("a", "a", True),
            ("ab/c", "a", False),
            ("a/b", "a/bc", False),
            ("a/../b", "a", True),
            ("a/../b", "b", False),
            ("../a", "..", True),
            ("a", ".", True),
            ("", ".", True),
            ("/a", ".", False),
            ("/a", "/", True),
            ("//a", "/", False),
            ("//a", "//", True),
            ("///a", "/", True),
            ("a//./b/", "a/b", True),
            ("A/b", "a", False),
            ("a\\b", "a", False),
            ("é/b", "é", False),
        ]
        for name, reference, expected in cases:
            with self.subTest(name=name, reference=reference):
                self.assertEqual(Path(name).is_relative_to(reference), expected)
                self.assertEqual(artifacts.is_referenced(name, {Path(reference)}), expected)
        self.assertFalse(artifacts.is_referenced("anything", set()))

    def test_seeded_reference_pools_match_both_original_filters(self):
        randomizer = random.Random(20260921)
        components = ["a", "A", "b", "..", ".", "file.o", "file.o2", "sp ace", "é", "é", "a\\b"]
        pool = ["", ".", "/", "//"] + [
            randomizer.choice(["", "/", "//", "///"])
            + randomizer.choice(["/", "//"]).join(
                randomizer.choices(components, k=randomizer.randrange(1, 8))
            )
            for _ in range(384)
        ]
        files = {name: {"fixture": i} for i, name in enumerate(pool)}
        for count in (0, 1, 7, 31, 127):
            for _ in range(4):
                references = randomizer.choices(pool, k=count)
                expected = {
                    name: value
                    for name, value in files.items()
                    if not any(Path(name).is_relative_to(Path(ref)) for ref in references)
                }
                with patch.object(artifacts, "inventory", return_value=files):
                    self.assertEqual(
                        artifacts.eligible(Path("/unused"), [], {"references": references}),
                        expected,
                    )
                reference_set = {Path(ref) for ref in references}
                self.assertEqual(
                    any(artifacts.is_referenced(name, reference_set) for name in files),
                    any(Path(name).is_relative_to(ref) for name in files for ref in references),
                )


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.expected_deletions = 1
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.name = "apps/ios/build/DerivedData/Build/Intermediates.noindex"
        self.cache = self.root / self.name
        self.cache.mkdir(parents=True)
        (self.cache / "object").write_bytes(b"rebuildable")
        self.protected = self.root / ".local/datasets/original"
        self.protected.parent.mkdir(parents=True)
        self.protected.write_bytes(b"private original")
        policy = {
            "reserve_gib": 20,
            "protected": [".local/datasets"],
            "rebuildable": [
                {
                    "path": self.name,
                    "consumers": ["builder"],
                    "reason": "object",
                    "rebuild": "make build",
                }
            ],
        }
        path = self.root / artifacts.POLICY
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps(policy))
        self.manifest = self.root / ".local/maintenance/preview.json"
        self.guard = patch.object(artifacts, "guard")
        self.guard.start()
        self.addCleanup(self.guard.stop)
        self.command = patch.object(artifacts, "command", return_value="a" * 40)
        self.command.start()
        self.addCleanup(self.command.stop)

    def plan(self):
        return artifacts.plan(self.root, self.manifest)

    def test_preview_delete_restart_and_rebuild_preserve_originals(self):
        self.plan()
        self.assertTrue((self.cache / "object").exists())
        result = artifacts.apply(self.root, self.manifest)
        self.assertEqual(result["deleted_files"], self.expected_deletions)
        self.assertEqual(self.protected.read_bytes(), b"private original")
        (self.cache / "object").write_bytes(b"rebuilt later")
        self.assertEqual(artifacts.apply(self.root, self.manifest), result)
        self.assertEqual((self.cache / "object").read_bytes(), b"rebuilt later")

    def test_peak_is_additional_and_cannot_bypass_the_reserve(self):
        with patch.object(
            artifacts.shutil, "disk_usage", return_value=SimpleNamespace(free=24 * artifacts.GIB)
        ):
            self.assertEqual(artifacts.space(self.root, 4)["reserve_gib"], 20)
            for peak in [4.1, -1, float("nan"), float("inf")]:
                with self.subTest(peak=peak), self.assertRaises(ValueError):
                    artifacts.space(self.root, peak)

    def test_new_changed_and_disappeared_files_refuse_deletion(self):
        self.plan()
        (self.cache / "new").write_bytes(b"active builder")
        with self.assertRaises(ValueError):
            artifacts.apply(self.root, self.manifest)

        (self.cache / "new").unlink()
        (self.cache / "object").write_bytes(b"changed")
        with self.assertRaises(ValueError):
            artifacts.apply(self.root, self.manifest)

    def test_unexplained_disappearance_is_rejected(self):
        self.plan()
        (self.cache / "object").unlink()
        with self.assertRaisesRegex(ValueError, "disappeared without"):
            artifacts.apply(self.root, self.manifest)

    def test_changed_protected_data_refuses_deletion(self):
        self.plan()
        self.protected.write_bytes(b"new reference")
        with self.assertRaisesRegex(ValueError, "Protected files changed"):
            artifacts.apply(self.root, self.manifest)
        self.assertTrue((self.cache / "object").exists())

    def test_replaced_parent_symlink_is_rejected(self):
        self.plan()
        (self.cache / "object").unlink()
        self.cache.rmdir()
        self.cache.symlink_to(self.protected.parent, target_is_directory=True)
        with self.assertRaises(ValueError):
            artifacts.apply(self.root, self.manifest)
        self.assertTrue(self.protected.exists())

    def test_plan_cannot_target_protected_files(self):
        value = self.plan()
        value["files"][".local/datasets/original"] = artifacts.fingerprint(self.protected)
        self.manifest.write_text(json.dumps(value))
        with self.assertRaises(ValueError):
            artifacts.apply(self.root, self.manifest)

    def test_tampered_plan_selecting_retained_ancestor_refuses_before_unlink(self):
        with patch.object(artifacts, "binary_consumers", return_value={"references": [self.name]}):
            value = self.plan()
            item = self.cache / "object"
            self.assertNotIn(str(item.relative_to(self.root)), value["files"])
            value["files"][str(item.relative_to(self.root))] = artifacts.fingerprint(item)
            self.manifest.write_text(json.dumps(value))
            with self.assertRaisesRegex(ValueError, "retained runtime/debug-map inputs"):
                artifacts.apply(self.root, self.manifest)
            self.assertEqual(item.read_bytes(), b"rebuildable")

    def test_interrupt_after_unlink_is_resumable(self):
        self.plan()
        real_inventory = artifacts.inventory
        calls = 0

        def interrupt(root, names):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise KeyboardInterrupt()
            return real_inventory(root, names)

        with patch.object(artifacts, "inventory", side_effect=interrupt):
            with self.assertRaises(KeyboardInterrupt):
                artifacts.apply(self.root, self.manifest)
        self.assertFalse((self.cache / "object").exists())
        self.assertEqual(
            artifacts.apply(self.root, self.manifest)["deleted_files"], self.expected_deletions
        )

    def test_symlink_in_preview_and_changed_policy_are_rejected(self):
        (self.cache / "reference").symlink_to(self.protected)
        with self.assertRaises(ValueError):
            self.plan()
        (self.cache / "reference").unlink()
        self.plan()
        with (self.root / artifacts.POLICY).open("a") as stream:
            stream.write("\n")
        with self.assertRaises(ValueError):
            artifacts.apply(self.root, self.manifest)

    def test_active_builder_and_open_candidate_are_rejected(self):
        self.guard.stop()

        def output(root, *args):
            return "987654 xcodebuild\n" if args[0] == "ps" else ""

        with patch.object(artifacts, "command", side_effect=output):
            with self.assertRaisesRegex(ValueError, "Active build"):
                artifacts.guard(self.root, [self.name])
        with (
            patch.object(artifacts, "command", return_value=""),
            patch.object(
                artifacts.subprocess,
                "run",
                return_value=type(
                    "Result",
                    (),
                    {"returncode": 0, "stderr": "", "stdout": f"p123\nn{self.cache}/object\n"},
                )(),
            ),
        ):
            with self.assertRaisesRegex(ValueError, "process is using"):
                artifacts.guard(self.root, [self.name])


class ConsumerCleanupTests(CleanupTests):
    def setUp(self):
        super().setUp()
        self.binary = self.root / ".local/builds/retained-test"
        self.binary.parent.mkdir(parents=True, exist_ok=True)
        self.binary.write_bytes(b"\xcf\xfa\xed\xfe" + b"binary identity")
        self.binary.chmod(0o755)
        self.references = []
        self.runtime_references = []
        self.failure = False

        def inspect(args, **kwargs):
            if self.failure:
                return SimpleNamespace(returncode=1, stderr="cannot inspect", stdout="")
            output = "\n".join("0000 - 00 0001 OSO " + n for n in self.references)
            runtime = "\n".join(
                "\t" + n + " (compatibility version 1.0.0, current version 1.0.0)"
                for n in self.runtime_references
            )
            return SimpleNamespace(
                returncode=0, stderr="", stdout=output if args[0] == "nm" else runtime
            )

        self.inspection = patch.object(artifacts.subprocess, "run", side_effect=inspect)
        self.inspection.start()
        self.addCleanup(self.inspection.stop)

    def test_existing_policy_retains_debugmap_input_and_original_binary(self):
        self.references = [str(self.cache / "object")]
        before = artifacts.sha(self.binary)
        plan = self.plan()
        self.assertNotIn(self.name + "/object", plan["files"])
        result = artifacts.apply(self.root, self.manifest)
        self.assertEqual(result["deleted_files"], self.expected_deletions - 1)
        self.assertEqual(artifacts.sha(self.binary), before)
        self.assertEqual((self.cache / "object").read_bytes(), b"rebuildable")
        self.assertEqual(result["protected_inventory"], plan["protected_inventory"])

    def test_relative_debugmap_reference_is_preserved(self):
        self.references = [self.name + "/object"]
        self.assertNotIn(self.name + "/object", self.plan()["files"])

    def test_changed_binary_or_new_consumer_refuses_before_unlink(self):
        self.plan()
        self.binary.write_bytes(b"\xcf\xfa\xed\xfe" + b"changed binary identity")
        with self.assertRaisesRegex(ValueError, "consumers changed"):
            artifacts.apply(self.root, self.manifest)
        self.assertTrue((self.cache / "object").exists())

    def test_new_binary_refuses_before_unlink(self):
        self.plan()
        newer = self.binary.with_name("new-consumer")
        newer.write_bytes(self.binary.read_bytes())
        newer.chmod(0o755)
        with self.assertRaisesRegex(ValueError, "consumers changed"):
            artifacts.apply(self.root, self.manifest)
        self.assertTrue((self.cache / "object").exists())

    def test_inspector_failure_refuses_plan(self):
        self.failure = True
        with self.assertRaisesRegex(ValueError, "Cannot inspect"):
            self.plan()
        self.assertFalse(self.manifest.exists())

    def test_generation_pending_refuses_plan(self):
        pending = self.root / ".local/builds/ios/product-generation-pending.json"
        pending.parent.mkdir(parents=True)
        pending.write_text("{}")
        with self.assertRaisesRegex(ValueError, "Pending product"):
            self.plan()

    def test_forged_symbol_candidate_is_rejected(self):
        self.references = [str(self.cache / "object")]
        plan = self.plan()
        plan["files"][self.name + "/object"] = artifacts.fingerprint(self.cache / "object")
        self.manifest.write_text(json.dumps(plan))
        with self.assertRaisesRegex(ValueError, "runtime/debug-map"):
            artifacts.apply(self.root, self.manifest)
        self.assertTrue((self.cache / "object").exists())

    def test_runtime_consumer_is_retained(self):
        self.runtime_references = [str(self.cache / "object")]
        self.assertNotIn(self.name + "/object", self.plan()["files"])

    def test_rpath_consumer_conservatively_preserves_matching_candidate(self):
        self.runtime_references = ["@rpath/object"]
        self.assertNotIn(self.name + "/object", self.plan()["files"])

    def test_completed_generation_maps_original_absolute_symbol_path(self):
        generation = self.root / ".local/builds/ios/generations" / ("1" * 32)
        cache = generation / "DerivedData/Index.noindex"
        cache.mkdir(parents=True)
        symbol = cache / "retained-symbol.o"
        symbol.write_bytes(b"original generation symbol")
        planned = {"schema_version": 1, "root": str(self.root), "identity": {"sha256": "d" * 64}}
        (generation / "plan.json").write_text(json.dumps(planned))
        receipt = {
            "schema_version": 1,
            "plan_sha256": artifacts.sha(generation / "plan.json"),
            "previous_location": ".local/builds/ios/DerivedData",
            "preserved_location": str((generation / "DerivedData").relative_to(self.root)),
            "new_identity": "d" * 64,
        }
        (generation / "receipt.json").write_text(json.dumps(receipt))
        path = self.root / artifacts.POLICY
        policy = json.loads(path.read_text())
        policy["protected"].append(".local/builds/ios/generations")
        policy["rebuildable"].append(
            {
                "path": str(cache.relative_to(self.root)),
                "consumers": ["old binary"],
                "reason": "index",
                "rebuild": "make build",
            }
        )
        path.write_text(json.dumps(policy))
        self.references = [
            str(self.root / ".local/builds/ios/DerivedData/Index.noindex/retained-symbol.o")
        ]
        plan = self.plan()
        self.assertNotIn(str(symbol.relative_to(self.root)), plan["files"])
        artifacts.apply(self.root, self.manifest)
        self.assertEqual(symbol.read_bytes(), b"original generation symbol")
        self.assertEqual(json.loads((generation / "receipt.json").read_text()), receipt)

    def test_initial_generation_without_prior_products(self):
        generation = self.root / ".local/builds/ios/generations" / ("3" * 32)
        generation.mkdir(parents=True)
        planned = {
            "schema_version": 1,
            "root": str(self.root),
            "identity": {"sha256": "new"},
            "previous_directory_existed": False,
            "previous_files": {},
        }
        receipt = {
            "schema_version": 1,
            "new_identity": "new",
            "previous_location": ".local/builds/ios/DerivedData",
            "preserved_location": None,
        }

        def save():
            (generation / "plan.json").write_text(json.dumps(planned))
            receipt["plan_sha256"] = artifacts.sha(generation / "plan.json")
            (generation / "receipt.json").write_text(json.dumps(receipt))

        save()
        self.assertEqual(artifacts.generation_locations(self.root), [])
        for key, value in [("previous_directory_existed", True), ("previous_files", {"file": {}})]:
            original = planned[key]
            planned[key] = value
            save()
            with self.assertRaisesRegex(ValueError, "empty product-generation"):
                artifacts.generation_locations(self.root)
            planned[key] = original
        save()
        (generation / "DerivedData").mkdir()
        with self.assertRaisesRegex(ValueError, "empty product-generation"):
            artifacts.generation_locations(self.root)

    def test_foreign_generation_root_is_rejected(self):
        generation = self.root / ".local/builds/ios/generations" / ("2" * 32)
        generation.mkdir(parents=True)
        (generation / "plan.json").write_text(
            json.dumps({"schema_version": 1, "root": "/foreign", "identity": {"sha256": "d" * 64}})
        )
        (generation / "receipt.json").write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "plan_sha256": artifacts.sha(generation / "plan.json"),
                    "previous_location": ".local/builds/ios/DerivedData",
                    "preserved_location": str((generation / "DerivedData").relative_to(self.root)),
                    "new_identity": "d" * 64,
                }
            )
        )
        with self.assertRaisesRegex(ValueError, "Invalid completed"):
            self.plan()

    def test_cleanup_lock_still_excludes_competing_cleanup(self):
        with artifacts.locked(self.root):
            with self.assertRaises(BlockingIOError):
                with artifacts.locked(self.root):
                    pass

    def test_preview_publication_never_overwrites_prior_evidence(self):
        self.plan()
        before = self.manifest.read_bytes()
        with self.assertRaises(FileExistsError):
            self.plan()
        self.assertEqual(self.manifest.read_bytes(), before)

    def test_0644_extensionless_macho_consumer_is_retained(self):
        self.binary.chmod(0o644)
        self.references = [str(self.cache / "object")]
        plan = self.plan()
        self.assertNotIn(self.name + "/object", plan["files"])
        self.assertIn(str(self.binary.relative_to(self.root)), plan["binary_consumers"]["files"])
        artifacts.apply(self.root, self.manifest)
        self.assertTrue((self.cache / "object").exists())

    def test_0644_dsym_and_framework_consumer_are_retained(self):
        for name in [
            "Example.dSYM/Contents/Resources/DWARF/Example",
            "Example.framework/Versions/A/Example",
        ]:
            path = self.root / ".local/builds/products" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(
                b"\xcf\xfa\xed\xfe"
                + b"\0" * 8
                + (10 if ".dSYM/" in name else 6).to_bytes(4, "little")
            )
            path.chmod(0o644)
        self.binary.unlink()  # Only synthetic low-permission consumers remain.
        self.references = [str(self.cache / "object")]
        plan = self.plan()
        self.assertNotIn(self.name + "/object", plan["files"])
        for name in [
            "Example.dSYM/Contents/Resources/DWARF/Example",
            "Example.framework/Versions/A/Example",
        ]:
            self.assertIn(".local/builds/products/" + name, plan["binary_consumers"]["files"])
        artifacts.apply(self.root, self.manifest)
        self.assertTrue((self.cache / "object").exists())

    def check_inspector_timeout(self, tool):
        def timeout(args, **kwargs):
            self.assertEqual(kwargs.get("timeout"), 30)
            if args[0] == tool:
                raise artifacts.subprocess.TimeoutExpired(args, 30)
            return SimpleNamespace(returncode=0, stderr="", stdout="")

        with patch.object(artifacts.subprocess, "run", side_effect=timeout):
            with self.assertRaisesRegex(ValueError, "timed out: " + tool):
                self.plan()
        self.assertFalse(self.manifest.exists())
        self.assertTrue((self.cache / "object").exists())

    def test_nm_timeout_is_finite_and_leaves_evidence_unchanged(self):
        self.check_inspector_timeout("nm")

    def test_otool_timeout_is_finite_and_leaves_evidence_unchanged(self):
        self.check_inspector_timeout("otool")

    def test_timeout_during_apply_stops_before_journal_or_unlink(self):
        self.plan()
        before = self.manifest.read_bytes()

        def timeout(args, **kwargs):
            self.assertEqual(kwargs.get("timeout"), 30)
            raise artifacts.subprocess.TimeoutExpired(args, 30)

        with patch.object(artifacts.subprocess, "run", side_effect=timeout):
            with self.assertRaisesRegex(ValueError, "timed out: nm"):
                artifacts.apply(self.root, self.manifest)
        self.assertTrue((self.cache / "object").exists())
        self.assertFalse(self.manifest.with_suffix(".journal.jsonl").exists())
        self.assertEqual(self.manifest.read_bytes(), before)


class CompilerCleanupTests(ConsumerCleanupTests):
    def setUp(self):
        super().setUp()
        self.expected_deletions = 4
        self.compiler_name = ".local/builds/rust/debug/deps"
        self.compiler = self.root / self.compiler_name
        self.compiler.mkdir(parents=True)
        self.archive = self.compiler / "libtiny-abcd.rlib"
        self.archive.write_bytes(b"!<arch>\ncompiled tiny archive")
        (self.compiler / "tiny-abcd.d").write_text("tiny-abcd: tiny.rs\n")
        self.metadata = self.compiler / "libtiny-abcd.rmeta"
        self.metadata.write_bytes(b"rust" + b"compiled tiny metadata")
        self.object = self.compiler / "tiny-abcd.unit.rcgu.o"
        self.object.write_bytes(
            b"\xcf\xfa\xed\xfe" + b"\0" * 8 + (1).to_bytes(4, "little") + b"object"
        )
        self.kept = {}
        for name in ["libreha_ffi.a", "libreha_ffi.dylib", "test-binary", "tiny-abcd.d"]:
            path = self.compiler / name
            if not path.exists():
                path.write_bytes(b"kept identity")
            self.kept[path] = path.read_bytes()
        diagnostic = self.compiler.parent / ".fingerprint/tiny/output-test-lib-tiny"
        diagnostic.parent.mkdir(parents=True)
        diagnostic.write_bytes(b"original failure diagnosis")
        self.kept[diagnostic] = diagnostic.read_bytes()
        weights = self.root / ".local/models/frozen/model.bin"
        weights.parent.mkdir(parents=True)
        weights.write_bytes(b"immutable weights")
        self.kept[weights] = weights.read_bytes()
        policy = json.loads((self.root / artifacts.POLICY).read_text())
        policy["protected"].extend([".local/builds/rust/debug", ".local/models"])
        policy["rebuildable"].append(
            {
                "path": self.compiler_name,
                "selector": "rust-debug-deps-compiler-v1",
                "consumers": ["Cargo offline"],
                "reason": "compiler files only",
                "rebuild": "cargo build --offline --locked",
            }
        )
        (self.root / artifacts.POLICY).write_text(json.dumps(policy))

    def test_selected_types_removed_and_all_protected_bytes_equal(self):
        plan = self.plan()
        for path in [self.archive, self.metadata, self.object]:
            self.assertIn(str(path.relative_to(self.root)), plan["files"])
        result = artifacts.apply(self.root, self.manifest)
        self.assertEqual(result["protected_inventory"], plan["protected_inventory"])
        for path, data in self.kept.items():
            self.assertEqual(path.read_bytes(), data)
        for path in [self.archive, self.metadata, self.object]:
            self.assertFalse(path.exists())

    def test_legacy_target_and_archive_member_debugmap_consumers_preserved(self):
        (self.root / "target").symlink_to(".local/builds/rust", target_is_directory=True)
        self.references = [
            str(self.root / "target/debug/deps" / self.archive.name) + "(tiny.member.o)",
            str(self.root / "target/debug/deps" / self.object.name),
        ]
        plan = self.plan()
        self.assertNotIn(str(self.archive.relative_to(self.root)), plan["files"])
        self.assertNotIn(str(self.object.relative_to(self.root)), plan["files"])
        self.assertNotIn(str(self.metadata.relative_to(self.root)), plan["files"])
        artifacts.apply(self.root, self.manifest)
        self.assertTrue(self.archive.exists())
        self.assertTrue(self.object.exists())

    def test_referenced_archive_protects_its_complete_compiler_family(self):
        self.references = [str(self.archive) + "(tiny.member.o)"]
        other = self.compiler / "libtiny-abce.rmeta"
        other.write_bytes(self.metadata.read_bytes())
        (self.compiler / "tiny-abce.d").write_text("tiny-abce: other.rs\n")
        paths = [self.archive, self.metadata, self.object]
        before = {p: artifacts.fingerprint(p) for p in paths}
        plan = self.plan()
        for path in paths:
            self.assertNotIn(str(path.relative_to(self.root)), plan["files"])
        self.assertIn(str(other.relative_to(self.root)), plan["files"])
        self.assertEqual(
            plan["binary_consumers"]["compiler_families"]["tiny-abcd"],
            sorted(str(p.relative_to(self.root)) for p in paths),
        )
        artifacts.apply(self.root, self.manifest)
        self.assertFalse(other.exists())
        for path in paths:
            self.assertEqual(artifacts.fingerprint(path), before[path])

    def test_referenced_saved_object_protects_matching_archive_and_metadata(self):
        self.references = [str(self.object)]
        plan = self.plan()
        for path in [self.archive, self.metadata, self.object]:
            self.assertNotIn(str(path.relative_to(self.root)), plan["files"])
        artifacts.apply(self.root, self.manifest)
        self.assertTrue(self.archive.exists())
        self.assertTrue(self.metadata.exists())

    def test_retained_llvm_archive_edge_preserves_complete_cargo_family(self):
        module = self.protected.parent / "index.bc"
        module.write_bytes(b"BC\xc0\xdecombined index fixture")
        target = self.archive

        class FakeReader:
            def __init__(self, root):
                pass

            def read(self, path):
                return {
                    "input": artifacts.llvm_references.fingerprint(path),
                    "references": [{"kind": "thinlto_module", "path": str(target)}],
                }

            def verify(self):
                pass

            def qualification(self):
                return {"identity": "pinned test reader"}

        paths = [self.archive, self.metadata, self.object]
        before = {path: artifacts.fingerprint(path) for path in paths}
        with patch.object(artifacts.llvm_references, "Reader", FakeReader):
            plan = self.plan()
            for path in paths:
                self.assertNotIn(str(path.relative_to(self.root)), plan["files"])
            self.assertEqual(
                plan["binary_consumers"]["compiler_families"]["tiny-abcd"],
                sorted(str(path.relative_to(self.root)) for path in paths),
            )
            artifacts.apply(self.root, self.manifest)
        for path in paths:
            self.assertEqual(artifacts.fingerprint(path), before[path])

    def test_changed_retained_family_metadata_refuses_before_unlink(self):
        self.references = [str(self.archive) + "(tiny.member.o)"]
        self.plan()
        self.metadata.write_bytes(b"rust" + b"changed protected family metadata")
        with self.assertRaisesRegex(ValueError, "Protected files changed"):
            artifacts.apply(self.root, self.manifest)
        self.assertFalse(self.manifest.with_suffix(".journal.jsonl").exists())
        self.assertTrue(self.object.exists())

    def test_unknown_format_refuses_before_any_removal(self):
        self.object.write_bytes(b"\xcf\xfa\xed\xfe" + b"\0" * 8 + (2).to_bytes(4, "little"))
        with self.assertRaisesRegex(ValueError, "supported compiler"):
            self.plan()
        self.assertTrue(self.archive.exists())

    def test_selector_cannot_authorize_dll_or_nested_file(self):
        plan = self.plan()
        dll = self.compiler / "libreha_ffi.dylib"
        plan["files"][str(dll.relative_to(self.root))] = artifacts.fingerprint(dll)
        self.manifest.write_text(json.dumps(plan))
        with self.assertRaisesRegex(ValueError, "reviewed checkout policy"):
            artifacts.apply(self.root, self.manifest)
        self.assertTrue(dll.exists())

    def test_unknown_selector_or_alias_root_rejected(self):
        path = self.root / artifacts.POLICY
        policy = json.loads(path.read_text())
        for selector, root in [
            ("arbitrary", self.compiler_name),
            ("rust-debug-deps-compiler-v1", "target/debug/deps"),
        ]:
            policy["rebuildable"][-1].update(path=root, selector=selector)
            path.write_text(json.dumps(policy))
            with self.assertRaises(ValueError):
                self.plan()

    def test_changed_nonselected_diagnostic_refuses_before_removal(self):
        self.plan()
        diagnostic = next(p for p in self.kept if ".fingerprint" in str(p))
        diagnostic.write_bytes(b"new unresolved failure")
        with self.assertRaisesRegex(ValueError, "Protected files changed"):
            artifacts.apply(self.root, self.manifest)
        self.assertTrue(self.archive.exists())

    def test_preserved_hardlink_keeps_original_bytes(self):
        original = self.protected.with_name("linked-original")
        os.link(self.archive, original)
        self.plan()
        artifacts.apply(self.root, self.manifest)
        self.assertFalse(self.archive.exists())
        self.assertEqual(original.read_bytes(), b"!<arch>\ncompiled tiny archive")

    def test_compiler_partial_unlink_resume_and_completed_replay(self):
        plan = self.plan()
        real_append = artifacts.append
        intents = 0

        def interrupt(path, event):
            nonlocal intents
            if event["action"] == "unlink-intent":
                intents += 1
                if intents == 3:
                    raise KeyboardInterrupt()
            real_append(path, event)

        with patch.object(artifacts, "append", side_effect=interrupt):
            with self.assertRaises(KeyboardInterrupt):
                artifacts.apply(self.root, self.manifest)
        result = artifacts.apply(self.root, self.manifest)
        self.assertEqual(result["protected_inventory"], plan["protected_inventory"])
        self.archive.write_bytes(b"!<arch>\nnew rebuild")
        self.assertEqual(artifacts.apply(self.root, self.manifest), result)
        self.assertEqual(self.archive.read_bytes(), b"!<arch>\nnew rebuild")

    def test_unreferenced_owned_macho_object_does_not_pin_itself(self):
        plan = self.plan()
        name = str(self.object.relative_to(self.root))
        self.assertIn(name, plan["files"])
        self.assertNotIn(name, plan["binary_consumers"]["files"])
        artifacts.apply(self.root, self.manifest)
        self.assertFalse(self.object.exists())

    def test_retained_object_debugmap_consumers_are_followed_transitively(self):
        dependent = self.compiler / "tiny-abcd.dependent.rcgu.o"
        dependent.write_bytes(self.object.read_bytes())

        def inspect(args, **kwargs):
            self.assertEqual(kwargs.get("timeout"), 30)
            refs = []
            if args[0] == "nm":
                if str(self.binary) in args:
                    refs.append(str(self.object))
                if str(self.object) in args:
                    refs.append(str(dependent))
            return SimpleNamespace(
                returncode=0, stderr="", stdout="\n".join("0000 - 00 0001 OSO " + n for n in refs)
            )

        with patch.object(artifacts.subprocess, "run", side_effect=inspect):
            plan = self.plan()
            for path in [self.object, dependent]:
                name = str(path.relative_to(self.root))
                self.assertNotIn(name, plan["files"])
                self.assertIn(name, plan["binary_consumers"]["files"])
            artifacts.apply(self.root, self.manifest)
        self.assertTrue(self.object.exists())
        self.assertTrue(dependent.exists())


class FormatBoundaryTests(CleanupTests):
    def test_non_darwin_plan_refuses_without_publication(self):
        with patch("sys.platform", "linux"):
            with self.assertRaisesRegex(ValueError, "Darwin/Mach-O only"):
                self.plan()
        self.assertFalse(self.manifest.exists())
        self.assertTrue((self.cache / "object").exists())

    def test_non_darwin_apply_refuses_before_journal_or_unlink(self):
        self.plan()
        with patch("sys.platform", "linux"):
            with self.assertRaisesRegex(ValueError, "Darwin/Mach-O only"):
                artifacts.apply(self.root, self.manifest)
        self.assertFalse(self.manifest.with_suffix(".journal.jsonl").exists())
        self.assertTrue((self.cache / "object").exists())

    def test_unsupported_retained_headers_refuse_plan(self):
        retained = self.root / "extensionless-0644"
        for header in [b"\x7fELF", b"BC\xc0\xde", b"\xde\xc0\x17\x0b", b"!<thin>\n"]:
            with self.subTest(header=header):
                self.manifest = self.manifest.with_name("preview-" + header.hex() + ".json")
                retained.write_bytes(header + str(self.cache / "object").encode())
                with self.assertRaisesRegex(ValueError, "Unsupported retained"):
                    self.plan()
                self.assertFalse(self.manifest.exists())
                self.assertTrue((self.cache / "object").exists())

    def test_new_unsupported_retained_headers_refuse_apply_without_unlink(self):
        self.plan()
        retained = self.root / "extensionless-0644"
        for header in [b"\x7fELF", b"BC\xc0\xde", b"\xde\xc0\x17\x0b", b"!<thin>\n"]:
            with self.subTest(header=header):
                retained.write_bytes(header + str(self.cache / "object").encode())
                with self.assertRaisesRegex(ValueError, "Unsupported retained"):
                    artifacts.apply(self.root, self.manifest)
                self.assertFalse(self.manifest.with_suffix(".journal.jsonl").exists())
                self.assertTrue((self.cache / "object").exists())

    def test_known_debug_lto_sidecars_refuse_even_without_magic(self):
        for suffix in [".dwo", ".dwp", ".thinlto.bc", ".imports"]:
            path = self.root / ("retained" + suffix)
            with self.subTest(suffix=suffix):
                self.manifest = self.manifest.with_name("preview" + suffix + ".json")
                path.write_bytes(b"")
                with self.assertRaisesRegex(ValueError, "debug/LTO sidecar"):
                    self.plan()
                self.assertFalse(self.manifest.exists())
                path.unlink()

    def test_embedded_archive_does_not_retain_external_object(self):
        archive = self.protected.with_suffix(".a")
        member = b"embedded copy; no external object reference\n"
        header = f"{'object/':<16}{0:<12}{0:<6}{0:<6}{'100644':<8}{len(member):<10}`\n".encode()
        content = b"!<arch>\n" + header + member
        archive.write_bytes(content)
        self.assertIn(self.name + "/object", self.plan()["files"])
        artifacts.apply(self.root, self.manifest)
        self.assertEqual(archive.read_bytes(), content)


class LLVMConsumerTests(CleanupTests):
    def setUp(self):
        super().setUp()
        self.module = self.protected.parent / "consumer.bc"
        self.module.write_bytes(b"BC\xc0\xdeverified fixture")
        self.edges = {}
        self.tool_identity = "pinned-reader"
        owner = self

        class FakeReader:
            def __init__(self, root):
                self.root = root

            def read(self, path):
                return {
                    "input": artifacts.llvm_references.fingerprint(path),
                    "references": [
                        {"kind": "thinlto_module", "path": str(target)}
                        for target in owner.edges.get(path, [])
                    ],
                }

            def verify(self):
                pass

            def qualification(self):
                return {"identity": owner.tool_identity}

        self.reader = patch.object(artifacts.llvm_references, "Reader", FakeReader)
        self.reader.start()
        self.addCleanup(self.reader.stop)

    def test_retained_llvm_references_protect_candidate_bytes(self):
        target = self.cache / "object"
        self.edges[self.module] = [target]
        plan = self.plan()
        self.assertNotIn(str(target.relative_to(self.root)), plan["files"])
        self.assertIn(
            str(self.module.relative_to(self.root)),
            plan["binary_consumers"]["llvm"]["files"],
        )
        artifacts.apply(self.root, self.manifest)
        self.assertEqual(target.read_bytes(), b"rebuildable")

    def test_unretained_candidate_module_may_disappear_without_snapshot_drift(self):
        candidate = self.cache / "candidate.bc"
        candidate.write_bytes(b"BC\xc0\xdecompiler cache")
        self.expected_deletions = 2
        self.module.unlink()  # No retained LLVM roots in this specific case.
        plan = self.plan()
        self.assertEqual(plan["binary_consumers"]["llvm"]["files"], {})
        self.assertIsNone(plan["binary_consumers"]["llvm"]["reader"])
        artifacts.apply(self.root, self.manifest)
        self.assertFalse(candidate.exists())

    def test_retained_llvm_edges_follow_other_modules_transitively(self):
        second = self.cache / "second.bc"
        second.write_bytes(b"BC\xc0\xdecompiler cache")
        self.edges[self.module] = [second]
        self.edges[second] = [self.cache / "object"]
        plan = self.plan()
        self.assertEqual(plan["files"], {})
        artifacts.apply(self.root, self.manifest)
        self.assertTrue(second.exists())

    def test_changed_reader_or_retained_module_refuses_before_unlink(self):
        self.plan()
        self.tool_identity = "changed"
        with self.assertRaisesRegex(ValueError, "consumers changed"):
            artifacts.apply(self.root, self.manifest)
        self.assertTrue((self.cache / "object").exists())
        self.assertFalse(self.manifest.with_suffix(".journal.jsonl").exists())

    def test_missing_local_reference_and_symlink_target_refuse(self):
        self.edges[self.module] = [self.cache / "missing"]
        with self.assertRaisesRegex(ValueError, "Missing local LLVM"):
            self.plan()
        alias = self.cache / "alias"
        alias.symlink_to(self.cache / "object")
        self.edges[self.module] = [alias]
        with self.assertRaisesRegex(ValueError, "Symbolic link"):
            self.plan()
        self.assertFalse(self.manifest.exists())


class CompilerFormatBoundaryTests(CompilerCleanupTests):
    def test_elf_and_bitcode_are_not_supported_compiler_objects(self):
        name = str(self.object.relative_to(self.root))
        elf = b"\x7fELF\x02\x01" + b"\0" * 10 + (1).to_bytes(2, "little")
        for content in [elf, b"BC\xc0\xde" + b"bitcode", b"\xde\xc0\x17\x0b" + b"wrapped"]:
            with self.subTest(content=content):
                self.object.write_bytes(content)
                with self.assertRaisesRegex(ValueError, "supported compiler"):
                    artifacts.compiler_file(self.root, name)

    def test_empty_object_is_preserved_and_explicitly_inventoried(self):
        self.object.write_bytes(b"")
        name = str(self.object.relative_to(self.root))
        before = artifacts.fingerprint(self.object)
        plan = self.plan()
        self.assertNotIn(name, plan["files"])
        self.assertEqual(plan["retained_empty_objects"], {name: before})
        result = artifacts.apply(self.root, self.manifest)
        self.assertEqual(artifacts.fingerprint(self.object), before)
        self.assertEqual(result["protected_inventory"], plan["protected_inventory"])
        self.assertFalse(self.archive.exists())
        self.assertFalse(self.metadata.exists())

    def test_filled_empty_object_refuses_before_other_files_are_removed(self):
        data = self.object.read_bytes()
        self.object.write_bytes(b"")
        self.plan()
        self.object.write_bytes(data)
        with self.assertRaisesRegex(ValueError, "empty object placeholders changed"):
            artifacts.apply(self.root, self.manifest)
        self.assertFalse(self.manifest.with_suffix(".journal.jsonl").exists())
        self.assertTrue(self.archive.exists())

    def test_empty_binary_check_metadata_is_preserved_and_inventoried(self):
        metadata = self.compiler / "libbinary_check-a123.rmeta"
        metadata.write_bytes(b"")
        (self.compiler / "binary_check-a123.d").write_text("binary_check-a123: main.rs\n")
        name = str(metadata.relative_to(self.root))
        before = artifacts.fingerprint(metadata)
        plan = self.plan()
        self.assertNotIn(name, plan["files"])
        self.assertEqual(plan["retained_empty_objects"], {name: before})
        result = artifacts.apply(self.root, self.manifest)
        self.assertEqual(artifacts.fingerprint(metadata), before)
        self.assertEqual(result["protected_inventory"], plan["protected_inventory"])
        self.assertFalse(self.archive.exists())
        self.assertFalse(self.metadata.exists())

    def test_filled_empty_metadata_refuses_before_any_unlink(self):
        data = self.metadata.read_bytes()
        self.metadata.write_bytes(b"")
        self.plan()
        self.metadata.write_bytes(data)
        with self.assertRaisesRegex(ValueError, "empty object placeholders changed"):
            artifacts.apply(self.root, self.manifest)
        self.assertFalse(self.manifest.with_suffix(".journal.jsonl").exists())
        self.assertTrue(self.archive.exists())

    def test_nonempty_unknown_metadata_still_refuses(self):
        self.metadata.write_bytes(b"unrecognized metadata bytes")
        with self.assertRaisesRegex(ValueError, "supported compiler"):
            self.plan()
        self.assertFalse(self.manifest.exists())
        self.assertTrue(self.archive.exists())


if __name__ == "__main__":
    unittest.main()
