"""Catch source-directory moves that XcodeGen otherwise omits from test targets."""

import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[3]


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


if __name__ == "__main__":
    unittest.main()
