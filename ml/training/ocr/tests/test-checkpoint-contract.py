"""Complete OCR recovery and selection evidence, without loading a model."""

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import contract
import export
import run_identity
import train


class CheckpointContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.run = Path(self.temp.name).resolve()
        contract.write(self.run / "identity.json", {"invented": True})
        contract.write(self.run / "settings.json", {"patience": 2, "max_epochs": 2})
        contract.write(self.run / "baseline.json", {"invented": True})
        self.metrics = {
            "overall": {"critical_errors": 0, "group_mean_error": 0.5, "character_errors": 2}
        }
        self.state = dict(
            epoch=2, steps=4, best_score=[0, 0.5, 2], best_epoch=1, stale_epochs=1, stopped=False
        )
        for epoch in (1, 2):
            path = self.run / "checkpoints" / f"epoch-{epoch:04d}"
            path.mkdir(parents=True)
            (path / "training.pdstate").write_bytes(b"invented checkpoint")
            contract.write(
                path / "checkpoint.json",
                dict(
                    epoch=epoch,
                    state=self.state
                    | {"epoch": epoch, "steps": epoch * 2, "stale_epochs": epoch - 1},
                    metrics=self.metrics,
                    training_sha256=contract.sha(path / "training.pdstate"),
                    run_identity=contract.sha(self.run / "identity.json"),
                    baseline_sha256=contract.sha(self.run / "baseline.json"),
                ),
            )
        (self.run / "selected.pdparams").write_bytes(b"invented selected model")
        (self.run / "export.yml").write_text("invented configuration")
        contract.write(
            self.run / "progress.json", self.state | {"status": "epoch-limit", "qualified": False}
        )
        contract.write(
            self.run / "selection.json",
            dict(
                epoch=1,
                metrics=self.metrics,
                qualified=False,
                sha256=contract.sha(self.run / "selected.pdparams"),
                export_config_sha256=contract.sha(self.run / "export.yml"),
            ),
        )

    def mutate(self, name, change):
        path = self.run / name
        value = json.loads(path.read_text())
        change(value)
        contract.write(path, value)

    def test_missing_empty_or_changed_baseline_binding_fails(self):
        name = "checkpoints/epoch-0002/checkpoint.json"
        original = (self.run / name).read_bytes()
        for value in (None, "", "changed"):
            with self.subTest(value=value):
                (self.run / name).write_bytes(original)
                self.mutate(
                    name,
                    lambda row: (
                        row.pop("baseline_sha256")
                        if value is None
                        else row.update(baseline_sha256=value)
                    ),
                )
                with self.assertRaises(ValueError):
                    train.latest_checkpoint(self.run)

    def test_directory_receipt_and_state_epoch_must_agree(self):
        name = "checkpoints/epoch-0002/checkpoint.json"
        original = (self.run / name).read_bytes()
        changes = [
            lambda row: row.update(epoch=1),
            lambda row: row.update(epoch=True),
            lambda row: row["state"].update(epoch=1),
            lambda row: row["state"].update(best_epoch=3),
            lambda row: row["state"].update(stale_epochs=0),
            lambda row: row["state"].update(stopped=True),
            lambda row: row["state"].update(best_score=[0, 0, 0]),
            lambda row: row.pop("metrics"),
        ]
        for change in changes:
            (self.run / name).write_bytes(original)
            change_name = changes.index(change)
            with self.subTest(change=change_name):
                self.mutate(name, change)
                with self.assertRaises(ValueError):
                    train.latest_checkpoint(self.run)

    def test_resume_validates_earlier_best_and_ignores_unpublished_epoch(self):
        (self.run / "checkpoints/.incomplete-next").mkdir()
        self.assertEqual(train.latest_checkpoint(self.run)[1]["epoch"], 2)
        self.mutate(
            "checkpoints/epoch-0001/checkpoint.json", lambda row: row.update(run_identity="changed")
        )
        with self.assertRaises(ValueError):
            train.latest_checkpoint(self.run)

    def test_selected_checkpoint_has_same_strict_contract(self):
        self.assertEqual(train.selected_checkpoint(self.run)[1]["epoch"], 1)
        self.mutate(
            "checkpoints/epoch-0001/checkpoint.json", lambda row: row["state"].update(epoch=2)
        )
        with self.assertRaises(ValueError):
            train.selected_checkpoint(self.run)

    def test_inconsistent_selection_and_incomplete_training_fail(self):
        name = "selection.json"
        original = (self.run / name).read_bytes()
        for change in [
            lambda row: row.update(epoch=True),
            lambda row: row.update(qualified=True),
            lambda row: row.update(sha256="changed"),
            lambda row: row.update(export_config_sha256="changed"),
            lambda row: row.update(metrics={}),
        ]:
            (self.run / name).write_bytes(original)
            self.mutate(name, change)
            with self.assertRaises(ValueError):
                train.selected_checkpoint(self.run)
        (self.run / name).write_bytes(original)
        self.mutate("progress.json", lambda row: row.update(status="running"))
        with self.assertRaises(ValueError):
            train.selected_checkpoint(self.run)

    def test_legacy_engine_retains_original_kernel_and_current_checkpoint_guard(self):
        contract.write(self.run / "settings.json", {"dataset": str(self.run / "dataset.json")})
        proof = {"mode": "archived-synthetic-v1"}
        with patch.object(run_identity, "verify", return_value=copy.deepcopy(proof)):
            engine, _ = run_identity.legacy_engine(self.run)
        self.assertEqual(
            Path(engine.execute.__code__.co_filename), run_identity.ARCHIVE / "train.py"
        )
        self.assertIs(engine.latest_checkpoint, train.latest_checkpoint)

    def test_export_rejects_incomplete_receipt_before_external_commands(self):
        self.mutate(
            "checkpoints/epoch-0001/checkpoint.json", lambda row: row.pop("baseline_sha256")
        )
        output = self.run / ".local/deployment"
        with (
            patch.object(export, "ROOT", self.run),
            patch.object(export, "validate_inputs", return_value=({}, {})),
            patch.object(export.subprocess, "run") as command,
            patch.object(
                sys, "argv", ["export.py", "--run", str(self.run), "--output", str(output)]
            ),
            self.assertRaises(ValueError),
        ):
            export.main()
        command.assert_not_called()
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
