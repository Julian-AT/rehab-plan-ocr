"""Recognition route identity, forced inference and retained-trace regressions."""

import contextlib
import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
from ml.evaluation.recognition import app_trial  # noqa: E402
from ml.evaluation.recognition.app_trial import complete, prepare_models, sha  # noqa: E402


class RecognitionAppTrialTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        (self.folder / "models").mkdir()
        self.trace = json.loads((ROOT / "ml/evaluation/fixtures/sample-run.json").read_text())
        self.trace["stages"].append({"name": "vision_refinement", "status": "complete"})
        self.manifest = self.trace["model_manifest"]
        manifest = self.folder / "models/manifest.json"
        manifest.write_text(json.dumps(self.manifest))
        self.request = dict(
            run_id="current",
            variant="baseline",
            source_sha256=self.trace["document"]["source_hash"],
            model_manifest_sha256=sha(manifest),
        )
        self.result = dict(
            self.request,
            stage="passed",
            qualified=False,
            calendar_operations=0,
            host_calls=dict(rejected_calendar_calls=0, native_reread_calls=2),
            cases=[],
        )
        for index in range(2):
            trace = copy.deepcopy(self.trace)
            trace["document"]["id"] = f"document-{index}"
            trace["cache_used"] = index == 1
            (self.folder / f"trace-{index}.json").write_text(json.dumps(trace))
            self.result["cases"].append(
                dict(
                    index=index,
                    document_id=f"document-{index}",
                    duplicate=False,
                    trace=f"trace-{index}.json",
                    import_seconds=1.0,
                    appointments=len(trace["appointments"]),
                )
            )

    def test_two_independent_forced_imports_retain_their_actual_models_and_source(self):
        complete(self.result, self.request, self.folder)

    def test_stale_partial_and_calendar_access_results_are_rejected(self):
        for key, value in [
            ("run_id", "old"),
            ("variant", "frozen"),
            ("stage", "started"),
            ("qualified", True),
            ("calendar_operations", False),
            ("calendar_operations", 1),
            ("host_calls", {"rejected_calendar_calls": 1}),
            ("host_calls", {"rejected_calendar_calls": False}),
            ("host_calls", {"rejected_calendar_calls": 0, "native_reread_calls": 0}),
            ("host_calls", {"rejected_calendar_calls": 0, "native_reread_calls": True}),
            ("model_manifest_sha256", "changed"),
            ("source_sha256", "changed"),
            ("cases", []),
            ("cases", [None]),
        ]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                complete(dict(self.result, **{key: value}), self.request, self.folder)

    def test_duplicates_trace_path_traversal_and_invalid_times_are_rejected(self):
        for key, value in [
            ("duplicate", True),
            ("trace", "../trace-0.json"),
            ("import_seconds", -1),
            ("import_seconds", True),
            ("import_seconds", float("nan")),
            ("appointments", 999),
        ]:
            result = copy.deepcopy(self.result)
            result["cases"][0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                complete(result, self.request, self.folder)

    def test_session_reuse_wrong_model_and_missing_inference_cannot_pass(self):
        path = self.folder / "trace-0.json"
        original = json.loads(path.read_text())
        for key, value in [
            ("cache_used", True),
            ("engine", "Apple Vision"),
            ("model_manifest", {}),
            ("stages", []),
            ("stages", [s for s in original["stages"] if s["name"] != "vision_refinement"]),
        ]:
            path.write_text(json.dumps(dict(original, **{key: value})))
            with self.subTest(key=key), self.assertRaises(ValueError):
                complete(self.result, self.request, self.folder)
        path.write_text(json.dumps(original))
        (self.folder / "models/manifest.json").write_text("{}")
        with self.assertRaises(ValueError):
            complete(self.result, self.request, self.folder)

    def test_only_known_experimental_variant_is_allowed(self):
        with self.assertRaises(ValueError):
            prepare_models(self.folder / "unwanted", "full", self.folder)
        self.assertFalse((self.folder / "unwanted").exists())


class AppTrialSourceBindingTests(unittest.TestCase):
    """Run the orchestration against invented files and a simulated app response."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.output = self.root / ".local/runs/trial"
        self.source = self.root / "ml/evaluation/fixtures/synthetic-day.png"
        self.card = self.root / "ml/registry/invented.json"
        self.evaluator = self.root / "ml/evaluation/recognition/app_trial.py"
        self.binary = (
            self.root
            / "build/DerivedData/Build/Products/Debug-iphonesimulator/Laßnitzhöhe.app/Termine.debug.dylib"
        )
        self.container = self.root / "container"
        (self.container / "Documents").mkdir(parents=True)
        for path in [
            self.source,
            self.card,
            self.evaluator,
            self.binary,
            self.root / "ml/evaluation/device/simulator.py",
            self.root / "ml/evaluation/conversation/native.py",
        ]:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("invented fixture " + path.name)
        self.original = sha(self.source)
        self.requests = []
        self.mutation = None

    def prepare(self, output, variant, **kwargs):
        if variant == "frozen" and self.mutation == "between-variants":
            self.source.write_text("different invented source")
        output.mkdir()
        manifest = {"engine": "simulated", "files": []}
        (output / "manifest.json").write_text(json.dumps(manifest))
        return manifest

    def fake_tool(self, command, **kwargs):
        if command[:2] == ["git", "ls-files"]:
            name = str(self.source.relative_to(self.root))
            return name if name in command else ""
        if command[:3] == ["xcrun", "simctl", "launch"]:
            folder = self.container / "Documents/recognition-probe"
            request = json.loads((folder / "input.json").read_text())
            self.requests.append(request)
            self.assertEqual(sha(folder / "input.png"), request["source_sha256"])
            manifest = json.loads((folder / "models/manifest.json").read_text())
            cases = []
            for index in range(2):
                trace = {
                    "document": {
                        "id": f"document-{index}",
                        "source_hash": request["source_sha256"],
                    },
                    "cache_used": index == 1,
                    "model_manifest": manifest,
                    "engine": manifest["engine"],
                    "stages": [
                        {"name": name, "status": "complete"}
                        for name in ["model_load", "recognition", "vision_refinement"]
                    ],
                    "appointments": [],
                }
                (folder / f"trace-{index}.json").write_text(json.dumps(trace))
                cases.append(
                    {
                        "index": index,
                        "document_id": f"document-{index}",
                        "duplicate": False,
                        "trace": f"trace-{index}.json",
                        "import_seconds": 1.0,
                        "appointments": 0,
                    }
                )
            result = dict(
                request,
                stage="passed",
                qualified=False,
                calendar_operations=0,
                host_calls={"rejected_calendar_calls": 0, "native_reread_calls": 2},
                cases=cases,
            )
            (folder / "result.json").write_text(json.dumps(result))
            if request["variant"] == "frozen" and self.mutation == "after-final-launch":
                self.source.write_text("changed after the final launch")
        return "simulated tool output"

    def evaluate(self):
        with contextlib.ExitStack() as stack:
            for name, value in {
                "ROOT": self.root,
                "__file__": str(self.evaluator),
                "run": self.fake_tool,
                "disposable": lambda *args: {"name": "invented disposable simulator"},
                "registry_path": lambda name: self.card,
                "install": lambda *args: self.container,
                "prepare_models": self.prepare,
            }.items():
                stack.enter_context(patch.object(app_trial, name, value))
            stack.enter_context(
                patch.object(app_trial.workspace, "location", return_value=self.root / "build")
            )
            stack.enter_context(
                patch.object(
                    sys,
                    "argv",
                    [str(self.evaluator), "--run", str(self.output), "--simulator", "simulated"],
                )
            )
            app_trial.main()

    def report(self):
        return json.loads((self.output / "report.json").read_text())

    def test_both_variants_use_the_one_frozen_original(self):
        self.evaluate()
        self.assertEqual(
            [request["source_sha256"] for request in self.requests], [self.original, self.original]
        )
        report = self.report()
        self.assertEqual(report["stage"], "compatibility_passed")
        self.assertEqual(report["source_sha256"], self.original)
        self.assertEqual(
            report["evaluation_sources"][str(self.source.relative_to(self.root))], self.original
        )
        self.assertFalse(report["qualified"])

    def test_changed_source_between_variants_stops_before_second_launch(self):
        self.mutation = "between-variants"
        with self.assertRaisesRegex(ValueError, "source|Source"):
            self.evaluate()
        self.assertEqual([request["variant"] for request in self.requests], ["baseline"])
        self.assertEqual(self.report()["stage"], "failed")
        self.assertEqual(self.report()["source_sha256"], self.original)

    def test_changed_source_after_final_launch_cannot_pass(self):
        self.mutation = "after-final-launch"
        with self.assertRaises(ValueError):
            self.evaluate()
        self.assertEqual(self.report()["stage"], "failed")
        self.assertEqual(self.report()["source_sha256"], self.original)

    def test_changed_copy_is_rejected_before_launch(self):
        copyfile = app_trial.shutil.copyfile

        def corrupt(source, destination, **kwargs):
            result = copyfile(source, destination, **kwargs)
            if source == self.source:
                Path(destination).write_text("different copied bytes")
            return result

        with patch.object(app_trial.shutil, "copyfile", side_effect=corrupt):
            with self.assertRaisesRegex(ValueError, "source|Source"):
                self.evaluate()
        self.assertEqual(self.requests, [])
        self.assertEqual(self.report()["stage"], "failed")


class FrozenPreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / ".local/models/runtime/small"
        self.source.mkdir(parents=True)
        registry = self.root / "ml/registry"
        (registry / "runtime").mkdir(parents=True)
        files = []
        for name in [
            "det-inference.onnx",
            "rec-inference.onnx",
            "det-inference.yml",
            "rec-inference.yml",
        ]:
            path = self.source / name
            path.write_text("invented fixture " + name)
            files.append(
                dict(path=name, bytes=path.stat().st_size, sha256=sha(path), url="synthetic")
            )
        dictionary = self.source / "dictionary.json"
        dictionary.write_text('["", "a"]')
        self.manifest = dict(engine="synthetic", files=files, dictionary_sha256=sha(dictionary))
        text = json.dumps(self.manifest)
        (self.source / "manifest.json").write_text(text)
        (registry / "runtime/small.lock.json").write_text(text)
        (registry / "ocr-base.json").write_text(
            json.dumps(dict(deployment_dictionary_sha256=sha(dictionary)))
        )
        self.training = self.root / ".local/runs/frozen"
        (self.training / "deployment").mkdir(parents=True)
        (self.training / "identity.json").write_text('{"synthetic": true}')
        model = self.training / "deployment/recognizer.onnx"
        model.write_text("invented adapted weights")
        self.variant = dict(
            mode="frozen-backbone",
            qualified=False,
            parity=dict(passed=True),
            run=".local/runs/frozen",
            run_identity_sha256=sha(self.training / "identity.json"),
            onnx_sha256=sha(model),
        )
        self.card = registry / "ocr-adaptation-smoke-002.json"
        self.card.write_text(json.dumps(dict(variants=[self.variant])))

    def test_only_recognizer_changes_and_original_bundle_stays_pinned(self):
        baseline = self.root / "baseline"
        frozen = self.root / "frozen"
        self.assertEqual(prepare_models(baseline, "baseline", self.root), self.manifest)
        manifest = prepare_models(frozen, "frozen", self.root)
        self.assertFalse(manifest["experimental"]["qualified"])
        self.assertEqual(sha(frozen / "dictionary.json"), self.manifest["dictionary_sha256"])
        self.assertEqual(sha(frozen / "det-inference.onnx"), sha(baseline / "det-inference.onnx"))
        self.assertNotEqual(
            sha(frozen / "rec-inference.onnx"), sha(baseline / "rec-inference.onnx")
        )
        self.assertEqual(
            sha(self.source / "rec-inference.onnx"), sha(baseline / "rec-inference.onnx")
        )

    def test_failed_parity_promoted_or_corrupt_training_inputs_stop_before_copy(self):
        for changes in [
            {"qualified": True},
            {"parity": {"passed": False}},
            {"run_identity_sha256": "changed"},
            {"onnx_sha256": "changed"},
            {"run": "../external"},
        ]:
            self.card.write_text(json.dumps(dict(variants=[dict(self.variant, **changes)])))
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                prepare_models(self.root / "rejected", "frozen", self.root)
            self.assertFalse((self.root / "rejected").exists())

    def test_new_registered_checkpoint_requires_unchanged_complete_export_evidence(self):
        checkpoint = self.training / "selected.pdparams"
        checkpoint.write_text("invented selected checkpoint")
        selection = self.training / "selection.json"
        selection.write_text(json.dumps(dict(sha256=sha(checkpoint))))
        parity = self.training / "deployment/parity.json"
        parity.write_text(
            json.dumps(
                dict(
                    passed=True,
                    artifact_sha256=self.variant["onnx_sha256"],
                    checkpoint_sha256=sha(checkpoint),
                )
            )
        )
        export = self.training / "deployment/export.json"
        export.write_text(
            json.dumps(
                dict(
                    status="desktop-parity-passed",
                    run_identity_sha256=self.variant["run_identity_sha256"],
                    selection_sha256=sha(selection),
                )
            )
        )
        self.variant.update(
            checkpoint_sha256=sha(checkpoint),
            evidence={
                str(p.relative_to(self.training)): sha(p) for p in [selection, parity, export]
            },
        )
        card = self.card.with_name("ocr-later-experiment.json")
        card.write_text(
            json.dumps(dict(promoted=False, physical_ios_verified=False, variants=[self.variant]))
        )
        manifest = prepare_models(self.root / "later", "frozen", self.root, card.name)
        self.assertEqual(manifest["experimental"]["registry_sha256"], sha(card))
        original_parity = parity.read_bytes()
        result = json.loads(original_parity)
        result["passed"] = False
        parity.write_text(json.dumps(result))
        self.variant["evidence"]["deployment/parity.json"] = sha(parity)
        card.write_text(
            json.dumps(dict(promoted=False, physical_ios_verified=False, variants=[self.variant]))
        )
        with self.assertRaisesRegex(ValueError, "matching export parity"):
            prepare_models(self.root / "rejected", "frozen", self.root, card.name)
        parity.write_bytes(original_parity)
        self.variant["evidence"]["deployment/parity.json"] = sha(parity)
        card.write_text(
            json.dumps(dict(promoted=False, physical_ios_verified=False, variants=[self.variant]))
        )
        for path in [selection, parity, export, checkpoint]:
            original = path.read_bytes()
            path.write_bytes(b"changed")
            with self.subTest(path=path), self.assertRaises(ValueError):
                prepare_models(self.root / "rejected", "frozen", self.root, card.name)
            path.write_bytes(original)
            self.assertFalse((self.root / "rejected").exists())

    def test_registry_paths_cannot_select_external_or_symlinked_cards(self):
        for name in ["../ocr-adaptation-smoke-002.json", str(self.card)]:
            with self.subTest(name=name), self.assertRaises(ValueError):
                prepare_models(self.root / "rejected", "frozen", self.root, name)
        link = self.card.with_name("linked.json")
        link.symlink_to(self.card)
        with self.assertRaises(ValueError):
            prepare_models(self.root / "rejected", "frozen", self.root, link.name)


if __name__ == "__main__":
    unittest.main()
