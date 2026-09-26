"""Optional crop readers must stop cleanly and retain comparison evidence."""

import importlib.util
import json
import platform
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "ml/evaluation/recognition"))
spec = importlib.util.spec_from_file_location(
    "compare_regions", ROOT / "ml/evaluation/recognition/compare-regions.py"
)
regions = importlib.util.module_from_spec(spec)
spec.loader.exec_module(regions)


class RegionComparisonTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.output = self.root / "output"
        self.run = self.root / "run.json"
        self.manifest = self.root / "manifest.json"
        self.run.write_text(json.dumps({"engine": "synthetic", "total_ms": 1, "appointments": []}))
        self.binary = self.root / "build/release/reha"
        self.binary.parent.mkdir(parents=True)
        self.binary.write_bytes(b"synthetic executable")
        lock = self.root / "ml/registry/runtime/vlm-experiments.lock.json"
        lock.parent.mkdir(parents=True)
        lock.write_text("{}")
        self.candidates = []
        for identifier in ["glm-ocr", "paddleocr-vl-1.6"]:
            candidate = {"id": identifier, "compatible": True}
            for name in ["model", "projector"]:
                path = self.root / f"{identifier}-{name}"
                path.write_bytes(b"synthetic checkpoint")
                candidate[name] = str(path)
                candidate[name + "_sha256"] = regions.sha(path)
            self.candidates.append(candidate)
        self.manifest.write_text(
            json.dumps(
                {
                    "binary": str(self.binary),
                    "binary_sha256": regions.sha(self.binary),
                    "lock_sha256": regions.sha(lock),
                    "runtime_revision": "synthetic",
                    "candidates": self.candidates,
                }
            )
        )

        def crop(*args, **kwargs):
            (self.output / "crop.json").write_text("{}")

        for patcher in [
            patch.object(regions, "ROOT", self.root),
            patch.object(regions.workspace, "cargo_directory", return_value=self.root / "build"),
            patch.object(regions.subprocess, "run", side_effect=crop),
            patch.object(platform, "platform", return_value="synthetic host"),
            patch.object(platform, "system", return_value="synthetic"),
        ]:
            patcher.start()
            self.addCleanup(patcher.stop)

    def child(self, returncode=None):
        child = Mock()
        child.returncode = returncode
        child.poll.side_effect = lambda: child.returncode
        child.kill.side_effect = lambda: setattr(child, "returncode", -9)
        child.wait.side_effect = lambda **kwargs: child.returncode
        return child

    def test_interruption_reaps_active_child_and_retains_completed_reader(self):
        completed, interrupted = self.child(0), self.child()
        children = iter([completed, interrupted])

        def start(command, **kwargs):
            # Even the first child starts only after the initial report is durable.
            self.assertTrue((self.output / "comparison.json").exists())
            if command[3] == "glm-ocr":
                Path(command[-1]).write_text(json.dumps({"status": "completed", "text": "fixture"}))
            return next(children)

        with (
            patch.object(regions.subprocess, "Popen", side_effect=start),
            patch.object(regions.time, "sleep", side_effect=KeyboardInterrupt),
            self.assertRaises(KeyboardInterrupt),
        ):
            regions.compare(self.run, self.output, self.manifest)
        completed.kill.assert_not_called()
        interrupted.kill.assert_called_once_with()
        interrupted.wait.assert_called_once_with(timeout=30)
        report = json.loads((self.output / "comparison.json").read_text())
        self.assertEqual([r["status"] for r in report["readers"]], ["completed", "unavailable"])
        self.assertEqual(report["readers"][0]["text"], "fixture")
        self.assertIn("KeyboardInterrupt", report["readers"][1]["reason"])
        self.assertFalse(report["packaging_eligible"])
        self.assertIsNone(report["verified_accuracy"])

    def test_deadline_reaps_child_and_keeps_existing_failure_contract(self):
        child = self.child()
        with (
            patch.object(regions.subprocess, "Popen", return_value=child),
            patch.object(regions.time, "monotonic", side_effect=[0, 60]),
        ):
            report = regions.compare(self.run, self.output, self.manifest, candidate_id="glm-ocr")
        child.kill.assert_called_once_with()
        child.wait.assert_called_once_with(timeout=30)
        self.assertEqual(report["readers"][0]["status"], "unavailable")
        self.assertIn("deadline or user cancellation", report["readers"][0]["reason"])
        self.assertEqual(report, json.loads((self.output / "comparison.json").read_text()))

    def test_cancel_file_stops_child_without_starting_another_reader(self):
        child = self.child()
        cancel = self.root / "cancel"
        with (
            patch.object(regions.subprocess, "Popen", return_value=child) as spawn,
            patch.object(regions.time, "sleep", side_effect=lambda _: cancel.touch()),
        ):
            report = regions.compare(self.run, self.output, self.manifest, cancel_file=cancel)
        spawn.assert_called_once()
        child.kill.assert_called_once_with()
        child.wait.assert_called_once_with(timeout=30)
        self.assertEqual(len(report["readers"]), 1)
        self.assertEqual(report, json.loads((self.output / "comparison.json").read_text()))

    def test_child_start_failure_is_saved_and_prior_output_cannot_be_replaced(self):
        with patch.object(regions.subprocess, "Popen", side_effect=OSError("synthetic failure")):
            report = regions.compare(self.run, self.output, self.manifest, candidate_id="glm-ocr")
        self.assertEqual(report["readers"][0]["reason"], "synthetic failure")
        original = (self.output / "comparison.json").read_bytes()
        with self.assertRaises(FileExistsError):
            regions.compare(self.run, self.output, self.manifest)
        self.assertEqual(original, (self.output / "comparison.json").read_bytes())


if __name__ == "__main__":
    unittest.main()
