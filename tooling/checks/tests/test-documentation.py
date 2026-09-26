"""Keep current documentation, the chosen visual reference and bundled notices coherent."""

import hashlib
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class DocumentationTests(unittest.TestCase):
    def test_current_documentation_links_resolve(self):
        # Model/evaluation guides, package READMEs and tooling instructions are
        # active documentation too. Stay in project-owned roots, outside .local
        # model copies, retained checkouts and third-party caches.
        documents = sorted(
            [
                *ROOT.glob("*.md"),
                *(
                    path
                    for name in ["apps", "config", "docs", "ml", "packages", "tooling"]
                    for path in (ROOT / name).rglob("*.md")
                ),
            ]
        )
        for document in documents:
            if document.is_relative_to(ROOT / "docs/releases/history"):
                # Historical reports identify the exact Git revision of retired assets.
                if document.name != "README.md":
                    self.assertIn("Historical record", document.read_text())
                continue
            for target in re.findall(r"\]\(([^)\n]+)\)", document.read_text()):
                if re.match(r"[a-z][a-z0-9+.-]*:|#|/", target, re.I):
                    continue
                with self.subTest(document=str(document.relative_to(ROOT)), target=target):
                    self.assertTrue((document.parent / target.split("#")[0]).exists())

    def test_visual_reference_is_complete_and_unchanged(self):
        folder = ROOT / "docs/product/visual-baseline"
        baseline = json.loads((folder / "baseline.json").read_text())
        self.assertFalse(baseline["full_app_regression_qualified"])
        self.assertEqual(
            {p.name for p in folder.glob("*.png")}, {v["file"] for v in baseline["images"]}
        )
        for entry in baseline["images"]:
            with self.subTest(image=entry["file"]):
                data = (folder / entry["file"]).read_bytes()
                self.assertEqual(len(data), entry["bytes"])
                self.assertEqual(hashlib.sha256(data).hexdigest(), entry["sha256"])

    def test_bundled_notices_match_manifest_exactly(self):
        folder = ROOT / "docs/third-party/licenses"
        manifest = json.loads((folder / "manifest.json").read_text())
        self.assertEqual({p.name for p in folder.iterdir()}, set(manifest) | {"manifest.json"})
        for name, expected in manifest.items():
            with self.subTest(notice=name):
                self.assertEqual(hashlib.sha256((folder / name).read_bytes()).hexdigest(), expected)

    def test_retired_assets_have_unique_recoverable_identities(self):
        inventory = json.loads((ROOT / "docs/releases/history/retired-assets.json").read_text())
        self.assertRegex(inventory["source_revision"], r"^[a-f0-9]{40}$")
        paths = [entry["path"] for entry in inventory["files"]]
        self.assertEqual(len(paths), len(set(paths)))
        for entry in inventory["files"]:
            self.assertTrue(
                entry["path"].startswith(("docs/preview/", "docs/third-party/licenses/"))
            )
            self.assertNotIn("..", Path(entry["path"]).parts)
            self.assertRegex(entry["sha256"], r"^[a-f0-9]{64}$")
            self.assertGreater(entry["bytes"], 0)
            self.assertFalse((ROOT / entry["path"]).exists())


if __name__ == "__main__":
    unittest.main()
