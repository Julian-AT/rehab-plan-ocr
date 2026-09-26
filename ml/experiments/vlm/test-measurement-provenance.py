"""Fake conversion and readers cannot attest bytes replaced during measurement."""

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "vlm_measured_fixture", Path(__file__).with_name("qualify-vlm.py")
)
qualifier = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(qualifier)
ACTUAL_RUN = qualifier.vlm_process.run


class MeasurementProvenanceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.args = SimpleNamespace(
            output=self.root / "new-evidence",
            runtime=self.root / "runtime",
            glm=self.root / "glm",
            paddle=self.root / "paddle",
            binary=self.root / "reader",
        )
        self.args.binary.write_bytes(b"reader")
        font = self.root / "font"
        font.write_bytes(b"font")
        self.args.runtime.mkdir()
        self.converter = self.args.runtime / "convert_hf_to_gguf.py"
        self.converter.write_bytes(b"converter")
        self.calls = []
        self.call_options = []
        self.mutation = None
        candidates = []
        for family, directory, names in [
            ("glm-ocr", self.args.glm, ["GLM-OCR-Q8_0.gguf", "mmproj-GLM-OCR-Q8_0.gguf"]),
            ("paddleocr-vl-1.6", self.args.paddle, ["config.json", "model.safetensors"]),
        ]:
            directory.mkdir()
            files = []
            for name in names:
                path = directory / name
                path.write_bytes(b"original")
                files.append({"path": name, "bytes": 8, "sha256": qualifier.sha(path)})
            candidate = {
                "id": family,
                "repository": "invented/repo",
                "revision": "a" * 40,
                "files": files,
            }
            candidates.append(candidate)
            (directory / "source-manifest.json").write_text(json.dumps(candidate))
        self.lock = self.root / "ml/registry/runtime/vlm-experiments.lock.json"
        self.lock.parent.mkdir(parents=True)
        self.lock.write_text(
            json.dumps({"runtime": {"revision": "b" * 40}, "candidates": candidates})
        )
        # The synthetic fixture is deliberately only bytes: no image library or model runs.
        pil = SimpleNamespace(
            Image=SimpleNamespace(
                new=lambda *a: SimpleNamespace(save=lambda path: path.write_bytes(b"image"))
            ),
            ImageDraw=SimpleNamespace(Draw=lambda *a: SimpleNamespace(text=lambda *a, **kw: None)),
            ImageFont=SimpleNamespace(truetype=lambda *a: None),
        )
        for manager in [
            patch.object(qualifier, "ROOT", self.root),
            patch.object(qualifier, "FONT_PATHS", [font]),
            patch.object(qualifier.vlm_process, "check_output", side_effect=self.git),
            patch.object(qualifier.vlm_process, "run", side_effect=self.child),
            patch.object(qualifier.importlib.metadata, "version", return_value="fixture"),
            patch.object(qualifier.platform, "system", return_value="Fixture"),
            patch.dict("sys.modules", {"PIL": pil}),
        ]:
            manager.start()
            self.addCleanup(manager.stop)

    def git(self, command, **kwargs):
        return "b" * 40 if "rev-parse" in command else ""

    def child(self, command, **kwargs):
        self.calls.append(command)
        self.call_options.append(kwargs)
        if "--outfile" in command:
            Path(command[command.index("--outfile") + 1]).write_bytes(b"converted")
        else:
            Path(command[-1]).write_text(
                json.dumps({"status": "complete", "text": "08:00 - 08:30 Bewegung Raum 2"})
            )
        if self.mutation:
            self.mutation(command)

    def receipt(self):
        return json.loads((self.args.output / "candidates.json").read_text())

    def test_unchanged_fake_children_retain_two_compatible_results(self):
        qualifier.qualify(self.args)
        result = self.receipt()
        self.assertEqual([item["compatible"] for item in result["candidates"]], [True, True])
        self.assertFalse(result["packaging_eligible"])
        self.assertEqual(len(self.calls), 4)

    def test_conversion_processes_have_finite_declared_deadlines(self):
        qualifier.qualify(self.args)
        for options in self.call_options[:2]:
            self.assertGreater(options["timeout"], 0)
            self.assertLessEqual(options["timeout"], 900)

    def test_real_hanging_fake_converter_retains_failed_evidence_and_log(self):
        def hang(command, **kwargs):
            return ACTUAL_RUN(
                [
                    sys.executable,
                    "-c",
                    "import time; print('invented converter',flush=True); time.sleep(60)",
                ],
                **kwargs,
            )

        self.args.phase_timeout_seconds = 0.3
        with (
            patch.object(qualifier.vlm_process, "run", side_effect=hang),
            self.assertRaises(subprocess.TimeoutExpired),
        ):
            qualifier.qualify(self.args)
        receipt = self.receipt()
        self.assertEqual(receipt["status"], "failed")
        self.assertIn("TimeoutExpired", receipt["error"])
        self.assertEqual(receipt["candidates"], [])
        self.assertFalse(receipt["packaging_eligible"])
        self.assertIn("invented converter", (self.args.output / "convert-text.log").read_text())

    def test_conversion_source_change_is_rejected_before_any_reader(self):
        self.mutation = lambda _: (self.args.paddle / "config.json").write_bytes(b"replaced")
        with self.assertRaisesRegex(ValueError, "changed"):
            qualifier.qualify(self.args)
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.receipt()["status"], "failed")
        self.assertFalse(any(item["compatible"] for item in self.receipt()["candidates"]))

    def test_converter_change_is_rejected_before_any_reader(self):
        self.mutation = lambda _: self.converter.write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "changed"):
            qualifier.qualify(self.args)
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.receipt()["status"], "failed")

    def test_changed_reader_artifact_or_input_cannot_have_a_compatible_receipt(self):
        for field in ["model", "projector", "image", "binary"]:
            with self.subTest(field=field):
                # Each attempt gets independent source and evidence directories.
                test = type(self)("test_unchanged_fake_children_retain_two_compatible_results")
                test.setUp()
                try:

                    def change(command):
                        if "--outfile" not in command:
                            index = {"model": 1, "projector": 2, "image": 4, "binary": 0}[field]
                            Path(command[index]).write_bytes(b"changed")

                    test.mutation = change
                    with self.assertRaisesRegex(ValueError, "changed"):
                        qualifier.qualify(test.args)
                    result = test.receipt()
                    self.assertEqual(result["status"], "failed")
                    self.assertFalse(any(item["compatible"] for item in result["candidates"]))
                    self.assertEqual(len(test.calls), 3)
                finally:
                    test.doCleanups()

    def test_reader_failure_still_records_incompatible_evidence(self):
        def fail(command):
            if "--outfile" not in command:
                raise qualifier.subprocess.CalledProcessError(1, command)

        self.mutation = fail
        qualifier.qualify(self.args)
        self.assertFalse(any(item["compatible"] for item in self.receipt()["candidates"]))

    def test_second_converter_cannot_replace_the_first_converted_artifact(self):
        def replace(command):
            if "--mmproj" in command:
                (self.args.output / "paddle-f16.gguf").write_bytes(b"changed")

        self.mutation = replace
        with self.assertRaisesRegex(ValueError, "changed"):
            qualifier.qualify(self.args)
        self.assertEqual(len(self.calls), 2)
        self.assertEqual(self.receipt()["status"], "failed")

    def test_later_change_invalidates_an_earlier_successful_candidate(self):
        def replace(command):
            if "--outfile" not in command and command[3] == "paddleocr-vl-1.6":
                (self.args.glm / "GLM-OCR-Q8_0.gguf").write_bytes(b"changed")

        self.mutation = replace
        with self.assertRaisesRegex(ValueError, "changed"):
            qualifier.qualify(self.args)
        result = self.receipt()
        self.assertEqual(result["status"], "failed")
        self.assertEqual([item["compatible"] for item in result["candidates"]], [False, False])


if __name__ == "__main__":
    unittest.main()
