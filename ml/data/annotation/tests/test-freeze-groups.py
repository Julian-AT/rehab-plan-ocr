import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "freeze", Path(__file__).parents[1] / "freeze_groups.py"
)
freeze = importlib.util.module_from_spec(spec)
spec.loader.exec_module(freeze)


class FreezeTests(unittest.TestCase):
    def test_transitive_speaker_dialogue_and_duplicate_source_leakage(self):
        entries = [
            dict(
                id=str(i),
                kind="speech",
                speaker_id=f"s{i}",
                related_ids=[],
                source_sha256=str(i) * 64,
            )
            for i in range(3)
        ]
        review = {
            str(i): dict(
                speaker_id=f"s{i}",
                dialogue_id="shared" if i < 2 else "other",
                partition="development" if i < 2 else "holdout",
            )
            for i in range(3)
        }
        result = freeze.partition(entries, review)
        self.assertEqual(len(result["groups"]), 2)
        self.assertFalse(result["training_authorized"])
        entries[2]["source_sha256"] = entries[1]["source_sha256"]
        with self.assertRaisesRegex(ValueError, "Related sources"):
            freeze.partition(entries, review)

    def test_layout_family_stays_together(self):
        entries = [
            dict(id=str(i), kind="schedule", related_ids=[], source_sha256=str(i) * 64)
            for i in range(2)
        ]
        review = {
            str(i): dict(
                plan_id=f"p{i}",
                revision_family=f"r{i}",
                layout_family="shared",
                partition="development" if i == 0 else "holdout",
            )
            for i in range(2)
        }
        with self.assertRaisesRegex(ValueError, "Related sources"):
            freeze.partition(entries, review)


if __name__ == "__main__":
    unittest.main()
