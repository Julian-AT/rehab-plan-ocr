"""Exercise the actual isolated CLI's failure paths without weights or private images."""

import argparse
import json
import tempfile
import unittest
from pathlib import Path

import vlm_process

ROOT = Path(__file__).resolve().parents[3]
BINARY = None
LIMIT = 40 * 1024 * 1024


class ReaderSmoke(unittest.TestCase):
    def setUp(self):
        scratch = ROOT / ".local/builds/vlm"
        scratch.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix=".smoke-", dir=scratch)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.image = self.root / "synthetic-invalid-image"
        self.image.write_bytes(b"not an image")
        self.output = self.root / "report.json"

    def invoke(self, image=None):
        return vlm_process.run(
            [
                str(BINARY),
                str(self.root / "missing.gguf"),
                str(self.root / "missing-projector.gguf"),
                "glm-ocr",
                str(image or self.image),
                str(self.output),
            ],
            text=True,
            capture_output=True,
            timeout=10,
        )

    def test_usage(self):
        result = vlm_process.run([str(BINARY)], capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 2)

    def test_missing_empty_and_directory_inputs_do_not_load_models(self):
        empty = self.root / "empty"
        empty.touch()
        for source in [self.root / "missing", empty, self.root]:
            with self.subTest(source=source.name):
                result = self.invoke(source)
                self.assertEqual(result.returncode, 2)
                self.assertNotIn("llama_model_load", result.stderr)
                self.assertFalse(self.output.exists())

    def test_sparse_oversized_input_is_rejected_before_reading_or_model_load(self):
        with self.image.open("wb") as stream:
            stream.truncate(64 * 1024**3)
        result = self.invoke()
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("llama_model_load", result.stderr)
        self.assertFalse(self.output.exists())

    def test_exact_size_limit_reaches_model_validation(self):
        with self.image.open("wb") as stream:
            stream.truncate(LIMIT)
        result = self.invoke()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(self.output.read_text())["status"], "incompatible_or_failed")

    def test_failed_model_never_reports_approval_or_success(self):
        result = self.invoke()
        self.assertEqual(result.returncode, 1)
        report = json.loads(self.output.read_text())
        self.assertEqual(report["status"], "incompatible_or_failed")
        self.assertFalse(report["approved"])
        self.assertEqual(report["text"], "")
        self.assertEqual(report["tokens"], 0)
        self.assertGreater(report["peak_rss_bytes"], 0)
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o600)

    def test_existing_report_is_preserved(self):
        original = b"retained earlier result\n"
        self.output.write_bytes(original)
        self.assertEqual(self.invoke().returncode, 3)
        self.assertEqual(self.output.read_bytes(), original)

    def test_report_symlink_does_not_touch_its_target(self):
        protected = self.root / "protected"
        protected.write_bytes(b"original")
        self.output.symlink_to(protected)
        self.assertEqual(self.invoke().returncode, 3)
        self.assertTrue(self.output.is_symlink())
        self.assertEqual(protected.read_bytes(), b"original")

    def test_unwritable_report_destination_fails(self):
        self.output = self.root / "missing-parent" / "report.json"
        self.assertEqual(self.invoke().returncode, 3)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    args = parser.parse_args()
    BINARY = args.binary.resolve(strict=True)
    unittest.main(argv=[__file__])
