"""Recognition route identity, forced inference and retained-trace regressions."""

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
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


if __name__ == "__main__":
    unittest.main()
