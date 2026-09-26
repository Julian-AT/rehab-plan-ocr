"""Leakage, missing evidence, validation stopping and interrupted checkpoint safety."""

import json
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import contract
import train


class TrainingContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.path = self.root / "dataset.json"
        self.dataset = {
            "schema_version": 1,
            "kind": "invented-smoke-text",
            "final_holdout": False,
            "samples": [],
        }
        for i, partition in enumerate(["train", "validation"]):
            image = self.root / f"{i}.png"
            Image.new("RGB", (20, 20), (i, 10, 10)).save(image)
            self.dataset["samples"].append(
                {
                    "id": str(i),
                    "partition": partition,
                    "state": "legible",
                    "text": "12:30",
                    "field": "start_time",
                    "group": f"group-{i}",
                    "source_sha256": contract.sha(image),
                    "image": image.name,
                    "image_sha256": contract.sha(image),
                }
            )

    def validate(self):
        self.path.write_text(json.dumps(self.dataset))
        return contract.validate_dataset(self.path, list("0123456789:"))

    def test_long_labels_preserved_and_unknown_characters_rejected(self):
        self.dataset["samples"][0]["text"] = "123" * 30
        self.assertEqual(len(self.validate()["samples"][0]["text"]), 90)
        self.dataset["samples"][0]["text"] += "☃"
        with self.assertRaisesRegex(ValueError, "discard"):
            self.validate()

    def test_related_sources_pixels_and_groups_cannot_cross_partitions(self):
        for key in ["group", "source_sha256", "image_sha256"]:
            with self.subTest(key=key):
                original = self.dataset["samples"][1][key]
                self.dataset["samples"][1][key] = self.dataset["samples"][0][key]
                with self.assertRaisesRegex(ValueError, "crosses"):
                    self.validate()
                self.dataset["samples"][1][key] = original

    def test_incomplete_labels_and_final_holdout_rejected(self):
        for state in ["cropped", "illegible", "contradictory", "not_printed", "uncertain"]:
            self.dataset["samples"][0]["state"] = state
            with self.assertRaisesRegex(ValueError, "Incomplete"):
                self.validate()
        self.dataset["samples"][0]["state"] = "legible"
        self.dataset["final_holdout"] = True
        with self.assertRaisesRegex(ValueError, "holdout"):
            self.validate()

    def test_mutated_pixels_and_missing_validation_fail(self):
        self.validate()
        (self.root / "0.png").write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "pixels changed"):
            self.validate()
        self.dataset["samples"] = [self.dataset["samples"][1]]
        with self.assertRaisesRegex(ValueError, "Nonempty"):
            self.validate()

    def test_critical_errors_take_priority_and_ties_stop(self):
        state = {"best_score": None, "stale_epochs": 0}
        best = {"critical_errors": 0, "group_mean_error": 0.4, "character_errors": 8}
        state = contract.advance(state, best, 1, 2)
        worse = {"critical_errors": 1, "group_mean_error": 0.1, "character_errors": 1}
        state = contract.advance(state, worse, 2, 2)
        self.assertEqual(state["best_epoch"], 1)
        self.assertFalse(state["stopped"])
        state = contract.advance(state, best, 3, 2)
        self.assertTrue(state["stopped"])
        with self.assertRaises(ValueError):
            contract.selection(best | {"group_mean_error": float("nan")})

    def test_time_aliases_are_canonical_and_unknown_fields_fail(self):
        self.assertEqual(contract.field_name("start"), "start_time")
        self.assertEqual(contract.field_name("end"), "end_time")
        self.dataset["samples"][0]["field"] = "strat_time"
        with self.assertRaisesRegex(ValueError, "Unknown OCR field"):
            self.validate()
        self.dataset["samples"][0]["field"] = "start"
        with self.assertRaisesRegex(ValueError, "canonical field"):
            self.validate()

    def test_groups_have_equal_weight_despite_derivative_counts(self):
        good = {
            "id": "a",
            "field": "start_time",
            "group": "a",
            "correct": True,
            "character_errors": 0,
            "expected": "1",
        }
        bad = good | {"group": "b", "correct": False, "character_errors": 1}
        metrics = train.summary([good] * 20 + [bad])
        self.assertEqual(metrics["group_mean_error"], 0.5)
        self.assertEqual(metrics["critical_errors"], 1)
        self.assertEqual(metrics["independent_groups"], 2)

    def test_incomplete_epoch_is_ignored_and_corruption_is_not_silently_resumed(self):
        (self.root / "identity.json").write_text("identity")
        contract.write(self.root / "settings.json", {"patience": 2, "max_epochs": 2})
        contract.write(self.root / "baseline.json", {"invented": True})
        checkpoint = self.root / "checkpoints/epoch-0001"
        checkpoint.mkdir(parents=True)
        weights = checkpoint / "training.pdstate"
        weights.write_bytes(b"invented checkpoint")
        contract.write(
            checkpoint / "checkpoint.json",
            {
                "epoch": 1,
                "state": {
                    "epoch": 1,
                    "steps": 1,
                    "best_epoch": 1,
                    "best_score": [0, 0, 0],
                    "stale_epochs": 0,
                    "stopped": False,
                },
                "metrics": {
                    "overall": {"critical_errors": 0, "group_mean_error": 0, "character_errors": 0}
                },
                "baseline_sha256": contract.sha(self.root / "baseline.json"),
                "training_sha256": contract.sha(weights),
                "run_identity": contract.sha(self.root / "identity.json"),
            },
        )
        (self.root / "checkpoints/.incomplete-epoch-2").mkdir()
        self.assertEqual(train.latest_checkpoint(self.root)[1]["epoch"], 1)
        weights.write_bytes(b"partial write")
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            train.latest_checkpoint(self.root)


if __name__ == "__main__":
    unittest.main()
