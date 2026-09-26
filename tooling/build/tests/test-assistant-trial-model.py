"""Experimental app comparisons must load exactly the selected registered artifact."""

import hashlib
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "assistant_trial_builder", Path(__file__).parents[1] / "build-assistant-trial.py"
)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class TrialModelTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        patcher = patch.object(builder, "ROOT", self.root)
        patcher.start()
        self.addCleanup(patcher.stop)
        (self.root / "ml/registry").mkdir(parents=True)
        (self.root / ".local/runs/example").mkdir(parents=True)
        self.paths = {}
        for variant, name in [
            ("tuned", "assistant-development-001"),
            ("tuned-v2", "assistant-development-002"),
            ("untuned", "assistant-untuned-001"),
        ]:
            model = self.root / ".local/runs/example" / (variant + ".gguf")
            data = ("invented model " + variant).encode()
            model.write_bytes(data)
            registry = dict(
                schema_version=1,
                id=name,
                qualified=False,
                artifact=dict(
                    format="GGUF-F16",
                    path=str(model.relative_to(self.root)),
                    bytes=len(data),
                    sha256=hashlib.sha256(data).hexdigest(),
                ),
            )
            path = self.root / "ml/registry" / (name + ".json")
            path.write_text(json.dumps(registry))
            self.paths[variant] = path

    def test_variants_use_distinct_registered_model_bytes(self):
        tuned = builder.model_artifact("tuned")
        candidate = builder.model_artifact("tuned-v2")
        baseline = builder.model_artifact("untuned")
        self.assertEqual(candidate[1]["id"], "assistant-development-002")
        self.assertEqual(len({v[1]["id"] for v in [tuned, candidate, baseline]}), 3)
        self.assertEqual(len({v[2].read_bytes() for v in [tuned, candidate, baseline]}), 3)
        with self.assertRaises(ValueError):
            builder.model_artifact("../unknown")

    def test_corrupt_or_replaced_artifacts_fail(self):
        _, _, model = builder.model_artifact("untuned")
        model.write_bytes(b"unrelated bytes")
        with self.assertRaises(ValueError):
            builder.model_artifact("untuned")

    def test_promoted_wrong_format_wrong_size_and_escaped_paths_fail(self):
        path = self.paths["tuned"]
        original = json.loads(path.read_text())
        for changes in [
            {"qualified": True},
            {"schema_version": 2},
            {"id": ""},
            {"artifact": dict(original["artifact"], format="unknown")},
            {"artifact": dict(original["artifact"], bytes=True)},
            {"artifact": dict(original["artifact"], bytes=500)},
            {"artifact": dict(original["artifact"], path="../../outside.gguf")},
        ]:
            path.write_text(json.dumps(dict(original, **changes)))
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                builder.model_artifact("tuned")

    def test_private_path_symlink_cannot_escape_into_other_storage(self):
        _, _, model = builder.model_artifact("untuned")
        outside = self.root / "unrelated.gguf"
        model.rename(outside)
        model.symlink_to(outside)
        with self.assertRaises(ValueError):
            builder.model_artifact("untuned")

    def test_voice_mode_cannot_select_another_model_before_build(self):
        with patch.object(builder, "source_snapshot") as snapshot:
            for model in ["untuned", "tuned"]:
                with self.assertRaises(ValueError):
                    builder.build_trial(model, 42, voice_ui_tests=True)
            snapshot.assert_not_called()

    def test_voice_receipt_requires_one_isolated_run_and_binds_runner_bytes(self):
        base = self.root / "trial"
        products = base / "DerivedData/Build/Products"
        products.mkdir(parents=True)
        run = products / "AssistantVoiceTrial_iphonesimulator26.0-arm64.xctestrun"
        runner = products / "Debug-iphonesimulator/AssistantVoiceTrialUITests-Runner.app"
        with patch.object(builder, "BASE", base):
            with self.assertRaisesRegex(ValueError, "one isolated"):
                builder.voice_test_products()
            run.write_bytes(b"invented xctestrun")
            with self.assertRaisesRegex(ValueError, "Missing"):
                builder.voice_test_products()
            runner.mkdir(parents=True)
            (runner / "runner").write_bytes(b"invented test code")
            receipt = builder.voice_test_products()
            self.assertEqual(receipt["scheme"], "AssistantVoiceTrial")
            self.assertEqual(receipt["xctestrun_sha256"], builder.assembly.sha(run))
            (runner / "runner").write_bytes(b"modified test code")
            self.assertNotEqual(
                receipt["runner_inventory"], builder.voice_test_products()["runner_inventory"]
            )
            (products / "AssistantVoiceTrial_iphonesimulator-stale.xctestrun").write_bytes(b"stale")
            with self.assertRaisesRegex(ValueError, "one isolated"):
                builder.voice_test_products()

    def test_voice_build_selects_only_separate_scheme_and_restores_project(self):
        commands = []

        def fail_xcode(*command):
            commands.append(command)
            if command[0] == "xcodebuild":
                self.assertIn("AssistantVoiceTrial", command)
                self.assertEqual(command[-1], "build-for-testing")
                raise subprocess.CalledProcessError(65, command)

        with (
            patch.object(builder, "BASE", self.root / "trial"),
            patch.object(builder, "source_snapshot", return_value={}),
            patch.object(builder, "prepare", return_value={}),
            patch.object(
                builder.product_generation,
                "delegate",
                return_value=subprocess.CompletedProcess([], 0),
            ),
            patch.object(builder, "run", side_effect=fail_xcode),
        ):
            with self.assertRaises(subprocess.CalledProcessError):
                builder.build_trial("tuned-v2", 42, voice_ui_tests=True)
        self.assertEqual(
            commands[-1],
            ("xcodegen", "generate", "--spec", "apps/ios/project.yml", "--project", "apps/ios"),
        )

    def test_active_native_build_refuses_trial_before_project_or_asset_work(self):
        generation = builder.product_generation
        with (
            patch.object(generation.workspace, "location", return_value=self.root / "build"),
            generation.locked(self.root),
            patch("sys.argv", ["trial", "--model", "untuned"]),
            patch.object(builder, "source_snapshot") as snapshot,
            patch.object(builder, "prepare") as prepare,
            patch.object(builder, "run") as run,
        ):
            with self.assertRaises(BlockingIOError):
                builder.main()
        snapshot.assert_not_called()
        prepare.assert_not_called()
        run.assert_not_called()

    def test_trial_restores_project_under_lease_after_failed_xcode(self):
        generation = builder.product_generation
        project = self.root / "project"
        project.write_text("ordinary project")

        def delegate(root, command, descriptor):
            self.assertEqual(root, self.root)
            self.assertEqual(command, ["sh", "tooling/build/build-native.sh", "simulator"])
            with patch.dict(os.environ, {generation.LEASE_DESCRIPTOR: str(descriptor)}):
                with generation.leased(root):
                    pass
            with self.assertRaises(BlockingIOError):
                with generation.locked(root):
                    self.fail("nested build lost the trial's lease")
            return subprocess.CompletedProcess(command, 0)

        def run(*command):
            with self.assertRaises(BlockingIOError):
                with generation.locked(self.root):
                    self.fail("project mutation escaped the trial's lease")
            if command[0] == "xcodebuild":
                self.assertEqual(project.read_text(), "trial project")
                raise subprocess.CalledProcessError(65, command)
            self.assertEqual(command[0], "xcodegen")
            project.write_text(
                "trial project" if "apps/ios/assistant-trial.yml" in command else "ordinary project"
            )

        with (
            patch.object(generation.workspace, "location", return_value=self.root / "build"),
            patch.object(builder, "BASE", self.root / "trial"),
            patch("sys.argv", ["trial", "--model", "untuned"]),
            patch.object(builder, "source_snapshot", return_value={}),
            patch.object(builder, "prepare", return_value={}),
            patch.object(generation, "delegate", side_effect=delegate),
            patch.object(builder, "run", side_effect=run),
        ):
            with self.assertRaises(subprocess.CalledProcessError):
                builder.main()
            self.assertEqual(project.read_text(), "ordinary project")
            with generation.locked(self.root):
                pass


if __name__ == "__main__":
    unittest.main()
