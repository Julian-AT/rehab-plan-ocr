"""Catch source-directory moves that XcodeGen otherwise omits from test targets."""

import json
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tooling/dev"))
import workspace  # noqa: E402


class ProjectPathsTests(unittest.TestCase):
    def test_every_declared_source_exists_without_private_model_assets(self):
        for project in [
            ROOT / "apps/ios/project.yml",
            ROOT / "apps/ios/IntegrationTests/project.yml",
        ]:
            data = yaml.safe_load(project.read_text())
            for target, settings in data["targets"].items():
                for source in settings.get("sources", []):
                    item = source if isinstance(source, dict) else {"path": source}
                    path = (project.parent / item["path"]).resolve()
                    with self.subTest(
                        project=str(project.relative_to(ROOT)), target=target, source=item
                    ):
                        if path.is_relative_to(ROOT / ".local/models"):
                            # Restored assets have their own hash verification; never exempt source code.
                            self.assertEqual(item.get("buildPhase"), "resources")
                            self.assertEqual(item.get("type"), "folder")
                        else:
                            self.assertTrue(path.exists(), f"Missing source: {path}")

    @unittest.skipUnless(sys.platform == "darwin", "Xcode project generation requires macOS")
    def test_generated_normal_and_trial_resource_closures_are_separate(self):
        env = workspace.environment()
        generator = shutil.which("xcodegen", path=env["PATH"])
        self.assertIsNotNone(generator)
        with tempfile.TemporaryDirectory(prefix="reha-project-resources-") as temporary:
            root = Path(temporary)
            ios = root / "apps/ios"
            ios.mkdir(parents=True)
            for name in ["project.yml", "assistant-trial.yml"]:
                source = ROOT / "apps/ios" / name
                shutil.copyfile(source, ios / name)
                spec = yaml.safe_load(source.read_text())
                for package in spec.get("packages", {}).values():
                    (ios / package["path"]).mkdir(parents=True, exist_ok=True)
                for target in spec["targets"].values():
                    for source in target.get("sources", []):
                        item = source if isinstance(source, dict) else {"path": source}
                        path = ios / item["path"]
                        if path.suffix:
                            path.parent.mkdir(parents=True, exist_ok=True)
                            path.write_text("{}")
                        else:
                            path.mkdir(parents=True, exist_ok=True)
            (ios / "Features/Public.txt").write_text("Ordinary app resource")
            prompt = "assistant-system-v1.txt"
            (ios / "Features/Conversation/Resources" / prompt).write_text("Trial prompt")

            for spec, trial in [("project.yml", False), ("assistant-trial.yml", True)]:
                with self.subTest(spec=spec):
                    subprocess.run(
                        [generator, "generate", "--spec", str(ios / spec), "--project", str(ios)],
                        env=env,
                        check=True,
                        capture_output=True,
                    )
                    project = json.loads(
                        subprocess.check_output(
                            [
                                "plutil",
                                "-convert",
                                "json",
                                "-o",
                                "-",
                                str(ios / "Termine.xcodeproj/project.pbxproj"),
                            ]
                        )
                    )["objects"]
                    target = next(
                        value
                        for value in project.values()
                        if value.get("isa") == "PBXNativeTarget" and value.get("name") == "Termine"
                    )
                    resources = [
                        Path(project[project[file]["fileRef"]]["path"]).name
                        for phase in target["buildPhases"]
                        if project[phase]["isa"] == "PBXResourcesBuildPhase"
                        for file in project[phase]["files"]
                    ]
                    self.assertIn("Public.txt", resources)
                    self.assertEqual(resources.count(prompt), int(trial))
                    self.assertEqual(resources.count("assistant-trial"), int(trial))
                    info = (
                        root / ".local/builds/assistant-app-trial/Info.plist"
                        if trial
                        else ios / "App/Info.plist"
                    )
                    self.assertEqual(
                        bool(plistlib.loads(info.read_bytes()).get("REHAExperimentalAssistant")),
                        trial,
                    )


if __name__ == "__main__":
    unittest.main()
