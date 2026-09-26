"""Portable leakage, review, intent and checkpoint-corruption regressions."""

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from ml.training.assistant import contract, prepare, train  # noqa: E402


class AssistantContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.path = self.root / "dataset.json"
        self.data = {
            "schema_version": 1,
            "kind": "invented-development-dialogues",
            "final_holdout": False,
            "samples": prepare.examples(0, 20260917),
        }

    def validate(self, data=None):
        self.path.write_text(json.dumps(data or self.data))
        return contract.validate_dataset(self.path)

    def test_invented_labels_cover_actions_and_keep_partial_changes_minimal(self):
        self.validate()
        cases = {r["family"]: r for r in self.data["samples"]}
        self.assertEqual(set(cases["rename-only"]["expected"]["change"]), {"title"})
        self.assertEqual(set(cases["duration-only"]["expected"]["change"]), {"duration"})
        self.assertEqual(cases["negative-remove"]["expected"], {"action": "cancel"})
        self.assertEqual(cases["negation-plus-change"]["expected"]["action"], "update")
        self.assertEqual(
            {r["expected"]["action"] for r in cases.values()},
            {"calendar", "create", "update", "remove", "cancel", "help", "clarify"},
        )

    def test_all_related_group_dimensions_must_stay_together(self):
        for group in ["family", "scenario_group", "paraphrase_group", "speaker_group"]:
            data = copy.deepcopy(self.data)
            valid = next(r for r in data["samples"] if r["partition"] == "validation")
            valid[group] = data["samples"][0][group]
            with self.subTest(group=group), self.assertRaisesRegex(ValueError, "cross partitions"):
                self.validate(data)

    def test_final_holdout_is_rejected(self):
        self.data["final_holdout"] = True
        with self.assertRaisesRegex(ValueError, "Final holdout"):
            self.validate()

    def test_invisible_reference_and_invalid_label_are_rejected(self):
        self.data["samples"][0]["context"]["selected"] = "hidden-calendar-event"
        with self.assertRaisesRegex(ValueError, "visible context"):
            self.validate()
        self.data["samples"][0]["context"]["selected"] = "termin-1"
        self.data["samples"][0]["expected"]["query"]["date"] = "2030-02-31"
        with self.assertRaisesRegex(ValueError, "Invalid calendar date"):
            self.validate()

    def test_duplicate_prompt_cannot_inflate_counts(self):
        row = copy.deepcopy(self.data["samples"][0])
        row["id"] = "another-id"
        self.data["samples"].append(row)
        with self.assertRaisesRegex(ValueError, "Duplicate prompt"):
            self.validate()

    def test_review_is_invalidated_by_changed_transcript(self):
        self.data["kind"] = "reviewed-development-dialogues"
        for row in self.data["samples"]:
            row["review"] = {
                "status": "approved",
                "reviewer": "synthetic-test-reviewer",
                "reviewed_at": "2030-01-01T12:00:00+00:00",
                "content_sha256": contract.digest(row),
            }
        self.validate()
        self.data["samples"][0]["utterance"] = "Die geänderte Äußerung wurde nicht freigegeben."
        with self.assertRaisesRegex(ValueError, "stale human"):
            self.validate()

    def test_selection_never_hides_unsafe_change_behind_lower_loss(self):
        good = {"unsafe_mutations": 0, "critical_errors": 2, "family_mean_error": 0.2, "loss": 2.0}
        unsafe = good | {"unsafe_mutations": 1, "critical_errors": 1, "loss": 0.1}
        state = {"stale_epochs": 0, "best_score": None}
        state = contract.advance(state, good, 1, 2)
        state = contract.advance(state, unsafe, 2, 2)
        state = contract.advance(state, unsafe, 3, 2)
        self.assertEqual(state["best_epoch"], 1)
        self.assertTrue(state["stopped"])

    def test_checkpoint_ignores_interrupted_directory_and_rejects_changed_optimizer(self):
        (self.root / "identity.json").write_text("{}")
        (self.root / "baseline.json").write_text("{}")
        parent = self.root / "checkpoints"
        (parent / ".incomplete-crash").mkdir(parents=True)
        self.assertEqual(train.latest_checkpoint(self.root), (None, None))
        completed = parent / "epoch-0001"
        completed.mkdir()
        names = [
            "adapters.safetensors",
            "optimizer.safetensors",
            "random.safetensors",
            "adapter_config.json",
            "metrics.json",
        ]
        for name in names:
            (completed / name).write_bytes(b"synthetic fixture")
        contract.write(
            completed / "checkpoint.json",
            {
                "epoch": 1,
                "run_identity": contract.sha(self.root / "identity.json"),
                "baseline_sha256": contract.sha(self.root / "baseline.json"),
                "files": {name: contract.sha(completed / name) for name in names},
            },
        )
        self.assertEqual(train.latest_checkpoint(self.root)[0], completed)
        (completed / "optimizer.safetensors").write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            train.latest_checkpoint(self.root)


if __name__ == "__main__":
    unittest.main()
