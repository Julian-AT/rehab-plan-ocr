"""Registration rejects incomplete/mixed evidence without hiding failed exports."""

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from model_card import checked_metrics, describe, distance, sha, summary


class ModelCardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.run = self.root / ".local/runs/invented"
        self.checkpoint = self.run / "checkpoints/epoch-0001"
        self.checkpoint.mkdir(parents=True)
        self.deployment = self.run / "deployment"
        self.deployment.mkdir()
        for name in [
            "identity.json",
            "selected.pdparams",
            "export.yml",
            "checkpoints/epoch-0001/training.pdstate",
            "deployment/recognizer.onnx",
        ]:
            (self.run / name).write_text("invented fixture: " + name)
        self.samples = [
            dict(id="a", partition="train"),
            dict(
                id="b",
                partition="validation",
                text="12:30",
                group="b",
                field="start_time",
                variant="original",
            ),
        ]
        row = dict(
            id="b",
            group="b",
            field="start_time",
            variant="original",
            expected="12:30",
            predicted="12:30",
            correct=True,
            character_errors=0,
        )
        self.metrics = dict(
            rows=[row],
            overall=summary([row]),
            originals=summary([row]),
            robustness=summary([]),
            new_critical_errors=[],
        )
        self.save(
            "settings.json",
            dict(mode="frozen-backbone", learning_rate=1e-4, width=320, patience=3, max_epochs=100),
        )
        self.progress = dict(
            status="validation-stopped",
            best_epoch=1,
            epoch=4,
            steps=4,
            best_score=[0, 0.0, 0],
            stale_epochs=3,
            stopped=True,
            qualified=False,
        )
        self.save("progress.json", self.progress)
        self.save("baseline.json", self.metrics)
        self.selection = dict(
            epoch=1,
            qualified=False,
            sha256=sha(self.run / "selected.pdparams"),
            export_config_sha256=sha(self.run / "export.yml"),
            metrics=self.metrics,
        )
        self.save("selection.json", self.selection)
        self.receipt = dict(
            epoch=1,
            run_identity=sha(self.run / "identity.json"),
            training_sha256=sha(self.checkpoint / "training.pdstate"),
            baseline_sha256=sha(self.run / "baseline.json"),
            metrics=self.metrics,
            state=dict(
                epoch=1,
                steps=1,
                best_epoch=1,
                best_score=[0, 0.0, 0],
                stale_epochs=0,
                stopped=False,
            ),
        )
        self.save("checkpoints/epoch-0001/checkpoint.json", self.receipt)
        last = self.run / "checkpoints/epoch-0004"
        last.mkdir()
        (last / "training.pdstate").write_bytes((self.checkpoint / "training.pdstate").read_bytes())
        self.save(
            "checkpoints/epoch-0004/checkpoint.json",
            self.receipt
            | {
                "epoch": 4,
                "state": {
                    key: value
                    for key, value in self.progress.items()
                    if key not in {"status", "qualified"}
                },
            },
        )
        self.parity = dict(
            artifact_sha256=sha(self.deployment / "recognizer.onnx"),
            checkpoint_sha256=self.selection["sha256"],
            onnxruntime="1.22.0",
            provider="CPUExecutionProvider",
            rtol=1e-3,
            atol=1e-5,
            quality_qualification=False,
            physical_ios_verified=False,
            passed=True,
            cases=[
                dict(id=r["id"], width=w, allclose=True, same_tokens=True, max_absolute_error=0.0)
                for r in self.samples
                for w in [320, 640]
            ],
        )
        self.export = dict(
            run_identity_sha256=sha(self.run / "identity.json"),
            selection_sha256=sha(self.run / "selection.json"),
            qualified=False,
            status="desktop-parity-passed",
            artifact_sha256=self.parity["artifact_sha256"],
        )
        self.save("deployment/parity.json", self.parity)
        self.save("deployment/export.json", self.export)

    def save(self, name, data):
        (self.run / name).write_text(json.dumps(data))

    def describe(self):
        return describe(self.run, {"samples": self.samples}, self.root)

    def test_passing_and_failed_exports_are_registered_without_private_labels_or_promotion(self):
        card = self.describe()
        self.assertFalse(card["qualified"])
        self.assertEqual(card["parity"]["cases"], 4)
        self.assertNotIn("12:30", json.dumps(card))
        self.assertEqual(card["selected_metrics"]["overall"]["exact"], 1)
        self.parity["cases"][0]["allclose"] = False
        self.parity["cases"][0]["max_absolute_error"] = 0.1
        self.parity["passed"] = False
        self.export["status"] = "interrupted-or-failed"
        self.save("deployment/parity.json", self.parity)
        self.save("deployment/export.json", self.export)
        failed = self.describe()
        self.assertFalse(failed["parity"]["passed"])
        self.assertEqual(failed["parity"]["numeric_cases_passed"], 3)
        self.assertFalse(failed["qualified"])

    def test_active_training_and_changed_weights_receipts_or_baseline_fail(self):
        self.save("progress.json", dict(self.progress, status="running"))
        with self.assertRaisesRegex(ValueError, "completed"):
            self.describe()
        self.save("progress.json", self.progress)
        for name in [
            "selected.pdparams",
            "export.yml",
            "identity.json",
            "baseline.json",
            "checkpoints/epoch-0001/training.pdstate",
            "deployment/recognizer.onnx",
        ]:
            path = self.run / name
            original = path.read_bytes()
            path.write_bytes(b"changed")
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.describe()
            path.write_bytes(original)

    def test_missing_duplicate_or_nonfinite_parity_and_changed_tolerance_fail(self):
        for changes in [
            {"cases": self.parity["cases"][:-1]},
            {"cases": [self.parity["cases"][0]] * 4},
            {"cases": [dict(r, max_absolute_error=float("nan")) for r in self.parity["cases"]]},
            {"atol": 1e-3},
            {"passed": False},
            {"onnxruntime": "other"},
            {"checkpoint_sha256": "other"},
            {"physical_ios_verified": True},
            {"diagnostic": True},
            {"graph_optimization": "GraphOptimizationLevel.ORT_DISABLE_ALL"},
        ]:
            self.save("deployment/parity.json", dict(self.parity, **changes))
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.describe()

    def test_metrics_recomputed_from_retained_labels_and_predictions(self):
        for edit in [
            lambda m: m["rows"].append(copy.deepcopy(m["rows"][0])),
            lambda m: m["rows"][0].update(expected="secret changed target"),
            lambda m: m["rows"][0].update(predicted="13:30"),
            lambda m: m["overall"].update(exact=2),
            lambda m: m["rows"][0].update(character_errors=99),
        ]:
            metrics = copy.deepcopy(self.metrics)
            edit(metrics)
            with self.assertRaises(ValueError):
                checked_metrics(metrics, self.samples)
        for a, b, expected in [
            ("", "abc", 3),
            ("abc", "", 3),
            ("12:30", "13:30", 1),
            ("Raum 1", "Raum 11", 1),
        ]:
            self.assertEqual(distance(a, b), expected)


if __name__ == "__main__":
    unittest.main()
