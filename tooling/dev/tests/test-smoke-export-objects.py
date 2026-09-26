import contextlib
import importlib.util
import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1]))
import model_objects as models
import smoke_export_objects as exports


@unittest.skipUnless(sys.platform == "darwin", "Requires macOS/APFS metadata APIs")
class ExportMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.files = []
        groups = []
        for number, suffix in [(1, "safetensors"), (2, "gguf")]:
            sources = [f".local/runs/assistant-smoke-003/model{number}.{suffix}"]
            targets = [
                f".local/runs/assistant-smoke-00{n}/model{number}.{suffix}"
                for n in ([1, 2] if number == 1 else [2])
            ]
            for i, name in enumerate(sources + targets):
                p = self.root / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_bytes(b"GGUF synthetic immutable fixture " + bytes([number]))
                p.chmod(0o640 if i else 0o644)
                os.utime(p, ns=(1_700_000_000_111_111_111, 1_700_000_000_222_222_222 + i))
                os.chflags(p, 0x8040)
                self.files.append({"path": name, **models.metadata(p)})
            value = models.identity(self.root / sources[0])
            groups.append(
                value
                | {
                    "retained_source": sources[0],
                    "targets": targets,
                    "possible_new_object": f".local/objects/sha256/{value['sha256']}.{suffix}",
                    "object_exists_at_review": False,
                }
            )
        self.proof = self.root / ".local/runs/assistant-smoke-001/failure.json"
        self.proof.write_bytes(b'{"historical_failure":"tokenizer"}')
        self.review = self.root / ".local/maintenance/review.json"
        self.review.parent.mkdir(parents=True)
        self.review.write_text(
            json.dumps(
                {
                    "root": str(self.root),
                    "groups": groups,
                    "files": self.files,
                    "retained_provenance_bindings": [
                        {
                            "path": str(self.proof.relative_to(self.root)),
                            "sha256": models.sha(self.proof),
                            "bytes": self.proof.stat().st_size,
                        }
                    ],
                }
            )
        )
        self.plan = self.review.with_name("plan.json")
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(exports, "GROUPS", groups))
        self.stack.enter_context(patch.object(exports, "REVIEW_SHA256", models.sha(self.review)))
        self.stack.enter_context(patch.object(exports, "guard"))
        self.fake_clone = self.stack.enter_context(
            patch.object(models, "clone", side_effect=shutil.copy2)
        )
        self.groups = groups
        self.source_inodes = [self.path(g["retained_source"]).stat().st_ino for g in groups]

    def path(self, name):
        return self.root / name

    def prepared(self):
        return exports.plan(self.root, self.review, self.plan)

    def assert_preserved(self):
        for row in self.files:
            self.assertEqual(
                models.metadata(self.path(row["path"])), {k: row[k] for k in models.METADATA_FIELDS}
            )
        self.assertEqual(
            [self.path(g["retained_source"]).stat().st_ino for g in self.groups], self.source_inodes
        )
        self.assertEqual(self.proof.read_bytes(), b'{"historical_failure":"tokenizer"}')

    def test_three_targets_keep_all_metadata_and_sources_replay(self):
        self.prepared()
        result = exports.apply(self.root, self.plan)
        self.assertEqual(result["preserved_target_paths"], 3)
        self.assert_preserved()
        self.assertEqual(exports.apply(self.root, self.plan), result)
        for group in self.groups:
            files = [
                self.path(n)
                for n in [group["retained_source"], *group["targets"], group["possible_new_object"]]
            ]
            self.assertEqual(len({p.stat().st_ino for p in files}), len(files))
            self.assertTrue(all(p.stat().st_nlink == 1 for p in files))
            self.assertEqual(files[-1].stat().st_mode & 0o777, 0o444)
        first = self.path(self.groups[0]["targets"][0])
        first.write_bytes(b"independent mutable replacement")
        self.assertNotEqual(
            first.read_bytes(), self.path(self.groups[0]["retained_source"]).read_bytes()
        )
        with self.assertRaisesRegex(ValueError, "export changed"):
            exports.apply(self.root, self.plan)

    def test_metadata_drift_refuses_before_first_replacement(self):
        self.prepared()
        p = self.path(self.groups[-1]["targets"][0])
        p.chmod(0o600)
        with self.assertRaisesRegex(ValueError, "export changed"):
            exports.apply(self.root, self.plan)
        self.fake_clone.assert_not_called()

    def test_all_existing_objects_checked_before_first_replacement(self):
        self.prepared()
        p = self.path(self.groups[-1]["possible_new_object"])
        p.parent.mkdir(parents=True)
        p.write_bytes(b"foreign")
        with self.assertRaisesRegex(ValueError, "object was altered"):
            exports.apply(self.root, self.plan)
        self.fake_clone.assert_not_called()

    def test_provenance_change_refuses(self):
        self.prepared()
        self.proof.write_bytes(b"changed failure receipt")
        with self.assertRaisesRegex(ValueError, "provenance changed"):
            exports.apply(self.root, self.plan)
        self.fake_clone.assert_not_called()

    def test_interruption_and_resume(self):
        self.prepared()
        real = models.verified_clone
        count = 0

        def interrupted(source, destination, expected):
            nonlocal count
            real(source, destination, expected)
            count += 1
            if count == 2:
                raise KeyboardInterrupt()

        with patch.object(models, "verified_clone", side_effect=interrupted):
            with self.assertRaises(KeyboardInterrupt):
                exports.apply(self.root, self.plan)
        self.assertFalse(self.plan.with_suffix(".receipt.json").exists())
        exports.apply(self.root, self.plan)
        self.assert_preserved()

    def test_hardlink_symlink_and_nonempty_xattrs_rejected(self):
        p = self.path(self.groups[0]["targets"][0])
        other = p.with_suffix(".other")
        os.link(p, other)
        with self.assertRaisesRegex(ValueError, "independent regular"):
            self.prepared()
        other.unlink()
        p.rename(other)
        p.symlink_to(other)
        with self.assertRaises(ValueError):
            self.prepared()
        p.unlink()
        other.rename(p)
        import subprocess

        subprocess.run(["/usr/bin/xattr", "-w", "com.reha.test", "fixture", str(p)], check=True)
        with self.assertRaisesRegex(ValueError, "extended attributes"):
            self.prepared()

    def test_destination_metadata_race_preserves_external_change(self):
        self.prepared()
        p = self.path(self.groups[0]["targets"][0])

        def changing(source, temporary):
            shutil.copy2(source, temporary)
            if temporary.parent == p.parent:
                p.chmod(0o600)

        with patch.object(models, "clone", side_effect=changing):
            with self.assertRaisesRegex(ValueError, "Destination changed"):
                exports.apply(self.root, self.plan)
        self.assertEqual(p.stat().st_mode & 0o777, 0o600)

    def test_unknown_scope_and_changed_review_rejected(self):
        value = json.loads(json.dumps(self.prepared()))
        value["groups"][0]["targets"][0] = ".local/models/original"
        self.plan.write_text(json.dumps(value))
        with self.assertRaisesRegex(ValueError, "stale export plan"):
            exports.apply(self.root, self.plan)
        self.review.write_text("{}")
        with self.assertRaisesRegex(ValueError, "exact independent"):
            exports.reviewed(self.root, self.review)

    def test_clone_failure_is_atomic(self):
        self.prepared()
        with patch.object(models, "clone", side_effect=OSError("unsupported filesystem")):
            with self.assertRaises(OSError):
                exports.apply(self.root, self.plan)
        self.assert_preserved()
        self.assertFalse(self.plan.with_suffix(".receipt.json").exists())

    def test_retained_source_inode_change_refuses(self):
        self.prepared()
        source = self.path(self.groups[0]["retained_source"])
        replacement = source.with_suffix(".replacement")
        shutil.copy2(source, replacement)
        os.chflags(replacement, source.stat().st_flags)
        replacement.replace(source)
        with self.assertRaisesRegex(ValueError, "source inode changed"):
            exports.apply(self.root, self.plan)
        self.fake_clone.assert_not_called()

    def test_busy_guard_and_independent_outer_lease_refuse(self):
        self.prepared()
        with patch.object(exports, "guard", side_effect=ValueError("active reader")):
            with self.assertRaisesRegex(ValueError, "active reader"):
                exports.apply(self.root, self.plan)
        import types

        @contextlib.contextmanager
        def busy(root):
            raise BlockingIOError("native product lease held")
            yield

        args = [
            "smoke_export_objects.py",
            "apply",
            "--review",
            str(self.review.relative_to(self.root)),
            "--manifest",
            str(self.plan.relative_to(self.root)),
        ]
        with (
            patch.object(exports, "ROOT", self.root),
            patch.object(sys, "argv", args),
            patch.dict(sys.modules, {"product_generation": types.SimpleNamespace(locked=busy)}),
        ):
            with self.assertRaisesRegex(BlockingIOError, "native product lease held"):
                exports.main()
        self.fake_clone.assert_not_called()

    def test_acl_is_rejected_before_clone(self):
        p = self.path(self.groups[0]["targets"][0])
        real = models.subprocess.check_output

        def output(args, **kwargs):
            if args[:2] == ["/bin/ls", "-lde"]:
                return "file\n 0: user:test allow read\n"
            return real(args, **kwargs)

        with patch.object(models.subprocess, "check_output", side_effect=output):
            with self.assertRaisesRegex(ValueError, "ACLs"):
                models.metadata(p)

    def test_real_apfs_tiny_clone_preserves_metadata_and_isolation(self):
        # No model file, compiler or root lease is touched: tiny isolated fixtures only.
        source = self.path(self.groups[0]["retained_source"])
        dest = self.path(self.groups[0]["targets"][0])
        expected = models.metadata(dest)
        clone_spec = importlib.util.spec_from_file_location("real_clone", Path(models.__file__))
        real = importlib.util.module_from_spec(clone_spec)
        clone_spec.loader.exec_module(real)
        with patch.object(models, "clone", side_effect=real.clone):
            models.verified_clone(source, dest, expected)
        self.assertEqual(models.metadata(dest), expected)
        self.assertNotEqual(source.stat().st_ino, dest.stat().st_ino)
        dest.write_bytes(b"isolated")
        self.assertNotEqual(dest.read_bytes(), source.read_bytes())


class MakeEntrypointTests(unittest.TestCase):
    def setUp(self):
        import subprocess

        self.run = subprocess.run
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.log = self.root / "calls.jsonl"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        fake = self.bin / "python3"
        fake.write_text(
            f"#!{sys.executable}\n"
            "import json, os, pathlib, sys\n"
            "if sys.argv[1:2] == ['tooling/dev/workspace.py']:\n"
            "    print('test-toolchain' if sys.argv[2] == 'toolchain' else "
            "str(pathlib.Path(os.environ['FIXTURE_ROOT']) / sys.argv[-1]))\n"
            "else:\n"
            "    with open(os.environ['FIXTURE_CALLS'], 'a') as stream:\n"
            "        stream.write(json.dumps(sys.argv[1:]) + '\\n')\n"
        )
        fake.chmod(0o755)
        self.makefile = Path(__file__).resolve().parents[3] / "Makefile"
        self.env = os.environ | {
            "PATH": str(self.bin) + os.pathsep + os.defpath,
            "FIXTURE_ROOT": str(self.root),
            "FIXTURE_CALLS": str(self.log),
        }
        for key in ("MAKEFLAGS", "MFLAGS", "MAKEOVERRIDES"):
            self.env.pop(key, None)

    def make(self, target, *variables, dry=False):
        result = self.run(
            [
                "/usr/bin/make",
                "--no-print-directory",
                "-f",
                str(self.makefile),
                *(["-n"] if dry else []),
                target,
                *variables,
            ],
            cwd=self.root,
            env=self.env,
            text=True,
            capture_output=True,
            timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def calls(self):
        return (
            [json.loads(line) for line in self.log.read_text().splitlines()]
            if self.log.exists()
            else []
        )

    def test_smoke_make_entrypoints_bind_exact_review_and_manifest(self):
        manifest = ".local/maintenance/smoke fixture.json"
        for target, action in [
            ("inventory-smoke-a-objects", "plan"),
            ("coalesce-smoke-a-objects", "apply"),
        ]:
            with self.subTest(target=target):
                self.make(target, "SMOKE_A_MANIFEST=" + manifest)
                self.assertEqual(
                    self.calls()[-1],
                    [
                        "tooling/dev/smoke_export_objects.py",
                        action,
                        "--review",
                        ".local/maintenance/assistant-smoke-a-cow-review-20260926-s21-001.json",
                        "--manifest",
                        manifest,
                    ],
                )
        self.assertEqual(len(self.calls()), 2)

    def test_baseline_make_entrypoints_remain_separate(self):
        manifest = ".local/maintenance/baseline fixture.json"
        for target, action in [
            ("inventory-model-objects", "plan"),
            ("coalesce-model-objects", "apply"),
        ]:
            with self.subTest(target=target):
                self.make(
                    target,
                    "MODEL_OBJECT_MANIFEST=" + manifest,
                    "SMOKE_A_MANIFEST=.local/maintenance/unrelated.json",
                )
                self.assertEqual(
                    self.calls()[-1],
                    ["tooling/dev/model_objects.py", action, "--manifest", manifest],
                )
        self.assertEqual(len(self.calls()), 2)

    def test_make_dry_runs_never_invoke_model_actions(self):
        for target, action in [
            ("inventory-smoke-a-objects", "plan"),
            ("coalesce-smoke-a-objects", "apply"),
        ]:
            with self.subTest(target=target):
                output = self.make(target, "SMOKE_A_MANIFEST=.local/maintenance/dry.json", dry=True)
                self.assertIn("smoke_export_objects.py " + action, output)
                self.assertIn("assistant-smoke-a-cow-review-20260926-s21-001.json", output)
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main()
