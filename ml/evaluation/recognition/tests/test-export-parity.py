"""Bind parity evidence to the files loaded by simulated model runtimes."""

import contextlib
import hashlib
import importlib.util
import json
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / "export_parity.py"


class Output:
    shape = (1, 1, 2)

    def numpy(self):
        return self

    def argmax(self, axis):
        return [1]

    def __sub__(self, other):
        return 0.0


class ExportParityBindingTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.run = Path(temporary.name).resolve()
        (self.run / "checkpoints").mkdir()
        self.checkpoint = self.run / "checkpoints/latest.pdparams"
        self.model = self.run / "recognizer.onnx"
        self.pixels = self.run / "one.png"
        self.dictionary = self.run / "dictionary.txt"
        self.config = self.run / "config.yml"
        for path in [self.checkpoint, self.model, self.pixels, self.dictionary]:
            path.write_text("invented bytes for " + path.name)
        self.config.write_text(
            json.dumps(
                {
                    "Global": {"character_dict_path": str(self.dictionary)},
                    "Architecture": {"Head": {}},
                }
            )
        )
        self.samples = self.run / "samples.jsonl"
        self.samples.write_text(
            json.dumps({"id": "one", "image_sha256": self.sha(self.pixels)}) + "\n"
        )
        self.original_model = self.sha(self.model)
        self.original_checkpoint = self.sha(self.checkpoint)
        self.after_inference = lambda: None
        self.loaded = []
        self.arguments = []
        self.validation_calls = 0
        self.validation_failure = False

    def prepare(self):
        self.checkpoint = self.run / "selected.pdparams"
        self.checkpoint.write_text("invented selected checkpoint")
        self.original_checkpoint = self.sha(self.checkpoint)
        self.config = self.run / "export.yml"
        self.config.write_bytes((self.run / "config.yml").read_bytes())
        self.dataset = self.run / "dataset.json"
        self.dataset.write_text(
            json.dumps(
                {
                    "samples": [
                        {"id": "one", "image": "one.png", "image_sha256": self.sha(self.pixels)}
                    ]
                }
            )
        )
        (self.run / "settings.json").write_text(
            json.dumps({"dataset": str(self.dataset), "width": 960})
        )
        (self.run / "selection.json").write_text(
            json.dumps(
                {"sha256": self.original_checkpoint, "export_config_sha256": self.sha(self.config)}
            )
        )
        (self.run / "identity.json").write_text('{"invented": true}')
        self.validator_source = self.run / "validator.py"
        self.validator_source.write_text("# invented validation source")

    @staticmethod
    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def evaluate(self):
        owner = self

        class Session:
            def __init__(self, path, **kwargs):
                owner.loaded.append(("onnx", owner.sha(Path(path))))

            def get_inputs(self):
                return [types.SimpleNamespace(name="input")]

            def run(self, *args):
                owner.after_inference()
                return [Output()]

        def load(path):
            owner.loaded.append(("checkpoint", owner.sha(Path(path))))
            return {}

        def validate(run):
            self.validation_calls += 1
            if self.validation_calls > 1 and self.validation_failure:
                raise ValueError("Prepared input review changed")
            return json.loads(self.dataset.read_text()), {
                "current_validation_sources": {
                    str(self.validator_source): self.sha(self.validator_source)
                },
                "run_identity_sha256": self.sha(run / "identity.json"),
                "dataset_sha256": self.sha(self.dataset),
            }

        stubs = {
            "cv2": types.ModuleType("cv2"),
            "numpy": types.SimpleNamespace(
                max=lambda value: value,
                abs=lambda value: value,
                allclose=lambda *args, **kwargs: True,
                array_equal=lambda a, b: a == b,
            ),
            "onnxruntime": types.SimpleNamespace(
                __version__="1.22.0",
                SessionOptions=lambda: types.SimpleNamespace(graph_optimization_level="enabled"),
                InferenceSession=Session,
            ),
            "paddle": types.SimpleNamespace(
                __version__="simulated",
                set_device=lambda value: None,
                load=load,
                no_grad=contextlib.nullcontext,
                to_tensor=lambda value: value,
            ),
            "yaml": types.SimpleNamespace(safe_load=json.loads),
            "PIL": types.SimpleNamespace(Image=None),
            "run_identity": types.SimpleNamespace(validate_inputs=validate),
            "ppocr.modeling.architectures": types.SimpleNamespace(),
        }

        class Model:
            def set_state_dict(self, state):
                pass

            def eval(self):
                pass

            def __call__(self, image):
                return Output()

        stubs["ppocr.modeling.architectures"].build_model = lambda config: Model()
        with (
            patch.dict(sys.modules, stubs),
            patch.object(sys, "argv", [str(SOURCE), "--run", str(self.run), *self.arguments]),
            patch.object(sys, "path", sys.path.copy()),
        ):
            spec = importlib.util.spec_from_file_location("parity_binding_test", SOURCE)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            module.normalized_image = lambda path, width: path.read_bytes()
            module.main()

    def report(self):
        return json.loads((self.run / "parity.json").read_text())

    def test_unchanged_files_match_both_loaded_identities_and_pass(self):
        self.evaluate()
        report = self.report()
        self.assertTrue(report["passed"])
        self.assertEqual(report["artifact_sha256"], self.original_model)
        self.assertEqual(report["checkpoint_sha256"], self.original_checkpoint)
        self.assertEqual(
            self.loaded, [("checkpoint", self.original_checkpoint), ("onnx", self.original_model)]
        )
        self.assertEqual(
            [(row["id"], row["width"]) for row in report["cases"]], [("one", 320), ("one", 640)]
        )

    def test_changed_measurement_inputs_cannot_receive_passing_evidence(self):
        for path in [
            self.model,
            self.checkpoint,
            self.config,
            self.dictionary,
            self.samples,
            self.pixels,
        ]:
            original = path.read_bytes()
            with self.subTest(path=path.name):
                self.after_inference = lambda path=path: path.write_bytes(
                    b"changed during inference"
                )
                with self.assertRaises(SystemExit):
                    self.evaluate()
                report = self.report()
                self.assertFalse(report["passed"])
                self.assertFalse(report["inputs_unchanged"])
                self.assertIn(str(path), report["input_changes"])
                self.assertEqual(report["artifact_sha256"], self.original_model)
                self.assertEqual(report["checkpoint_sha256"], self.original_checkpoint)
            path.write_bytes(original)
            (self.run / "parity.json").unlink(missing_ok=True)

    def test_removed_model_retains_failure_evidence_for_the_original_artifact(self):
        self.after_inference = lambda: self.model.unlink(missing_ok=True)
        with self.assertRaises(SystemExit):
            self.evaluate()
        report = self.report()
        self.assertFalse(report["passed"])
        self.assertEqual(report["artifact_sha256"], self.original_model)
        self.assertIsNone(report["input_changes"][str(self.model)]["actual_sha256"])

    def test_prepared_run_revalidates_inputs_and_preserves_dynamic_widths(self):
        self.prepare()
        self.evaluate()
        self.assertTrue(self.report()["passed"])
        self.assertEqual([row["width"] for row in self.report()["cases"]], [320, 640, 960])
        self.assertEqual(self.validation_calls, 2)

    def test_changed_prepared_inputs_fail_with_original_loaded_hash(self):
        self.prepare()
        for path in [
            self.run / "selection.json",
            self.run / "settings.json",
            self.run / "identity.json",
            self.dataset,
            self.validator_source,
        ]:
            original = path.read_bytes()
            with self.subTest(path=path.name):
                self.after_inference = lambda path=path: path.write_text("{}")
                with self.assertRaises(SystemExit):
                    self.evaluate()
                self.assertFalse(self.report()["passed"])
                self.assertIn(str(path), self.report()["input_changes"])
                self.assertEqual(self.report()["checkpoint_sha256"], self.original_checkpoint)
            path.write_bytes(original)
            (self.run / "parity.json").unlink()

    def test_mid_measurement_input_removal_keeps_an_incomplete_failed_report(self):
        self.after_inference = lambda: self.pixels.unlink(missing_ok=True)
        with self.assertRaises(SystemExit):
            self.evaluate()
        report = self.report()
        self.assertFalse(report["passed"])
        self.assertEqual(len(report["cases"]), 1)
        self.assertIsNotNone(report["measurement_error"])
        self.assertIn(str(self.pixels), report["input_changes"])

    def test_failed_final_prepared_validation_retains_failure_evidence(self):
        self.prepare()
        self.validation_failure = True
        with self.assertRaises(SystemExit):
            self.evaluate()
        report = self.report()
        self.assertFalse(report["passed"])
        self.assertFalse(report["inputs_unchanged"])
        self.assertEqual(report["input_validation_error"], "Prepared input review changed")

    def test_changed_subset_keeps_its_original_hash_and_never_passes(self):
        subset = self.run / "previous.json"
        subset.write_text(
            json.dumps(
                {
                    "artifact_sha256": self.original_model,
                    "checkpoint_sha256": self.original_checkpoint,
                    "cases": [{"id": "one", "width": 640, "allclose": False, "same_tokens": True}],
                }
            )
        )
        original = self.sha(subset)
        self.arguments = ["--failures-from", str(subset)]
        self.after_inference = lambda: subset.write_text("{}")
        with self.assertRaises(SystemExit):
            self.evaluate()
        report = self.report()
        self.assertFalse(report["passed"])
        self.assertEqual(report["subset_source_sha256"], original)
        self.assertEqual([row["width"] for row in report["cases"]], [640])

    def test_changed_model_symlink_target_cannot_pass(self):
        alternate = self.run / "alternate.onnx"
        alternate.write_text("different invented model")
        link = self.run / "model-link.onnx"
        link.symlink_to(self.model)
        self.arguments = ["--onnx", str(link)]

        def replace():
            link.unlink()
            link.symlink_to(alternate)

        self.after_inference = replace
        with self.assertRaises(SystemExit):
            self.evaluate()
        self.assertFalse(self.report()["passed"])
        self.assertIn(str(link), self.report()["input_changes"])
        self.assertEqual(self.report()["artifact_sha256"], self.original_model)


if __name__ == "__main__":
    unittest.main()
