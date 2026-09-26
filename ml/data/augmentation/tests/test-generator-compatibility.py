"""Augmentation must validate source bytes with the matching retained renderer."""

import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "augmentation_verifier", Path(__file__).resolve().parents[1] / "verify.py"
)
verify = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verify)


class GeneratorCompatibilityTests(unittest.TestCase):
    def test_matching_current_and_frozen_renderers_are_selected(self):
        for version, filename in [(2, "compat/synthetic_plans_v2.py"), (3, "synthetic-plans.py")]:
            source = verify.ROOT / "ml/data/synthesis" / filename
            renderer = verify.source_renderer(
                {
                    "schema_version": version,
                    "synthetic": True,
                    "generator_sha256": verify.sha(source),
                }
            )
            self.assertEqual(renderer.VERSION, version)
            self.assertEqual(Path(renderer.__file__), source)

    def test_renderer_substitution_unknown_versions_and_unverified_sources_fail(self):
        current = verify.sha(verify.ROOT / "ml/data/synthesis/synthetic-plans.py")
        for manifest in [
            {"schema_version": 2, "synthetic": True, "generator_sha256": current},
            {"schema_version": 3, "synthetic": False, "generator_sha256": current},
            {"schema_version": 4, "synthetic": True, "generator_sha256": current},
        ]:
            with self.assertRaisesRegex(ValueError, "verified synthetic"):
                verify.source_renderer(manifest)


if __name__ == "__main__":
    unittest.main()
