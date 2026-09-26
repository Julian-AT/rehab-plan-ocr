"""Portable interruption-harness deadlines; synthetic subprocesses never load models."""

import io
import json
import os
import signal
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from ml.training.assistant import contract  # noqa: E402
from ml.training.assistant import verify_interruption as proof  # noqa: E402


class InterruptionProcessTests(unittest.TestCase):
    def setUp(self):
        self.children = []
        spawn = subprocess.Popen

        def record(*args, **kwargs):
            child = spawn(*args, **kwargs)
            self.children.append(child)
            return child

        self.patcher = patch.object(proof.subprocess, "Popen", side_effect=record)
        self.patcher.start()
        self.addCleanup(self.patcher.stop)
        self.addCleanup(self.cleanup_children)

    def cleanup_children(self):
        for child in self.children:
            if child.poll() is None:
                child.kill()
                child.wait(timeout=5)
            child.stdout.close()

    def execute(self, code, log, timeout=2):
        return proof.interrupt_at_step(
            [sys.executable, "-c", code], log, dict(os.environ), 12, timeout
        )

    def test_silent_and_partial_line_children_time_out_and_are_reaped(self):
        for output in [b"", b"STEP 12 epoch=2 loss=1"]:
            with self.subTest(output=output):
                log = io.BytesIO()
                with self.assertRaises(subprocess.TimeoutExpired):
                    self.execute(
                        f"import os,time; os.write(1,{output!r}); time.sleep(60)", log, timeout=1
                    )
                self.assertEqual(log.getvalue(), output)
                self.assertEqual(self.children[-1].returncode, -signal.SIGKILL)
                self.assertTrue(self.children[-1].stdout.closed)

    def test_complete_trigger_line_is_logged_and_terminates_the_child(self):
        log = io.BytesIO()
        result = self.execute(
            "import os,time; os.write(1,b'STEP 12 epoch=2 loss=1\\n'); time.sleep(60)", log
        )
        self.assertEqual(result, (True, -signal.SIGTERM))
        self.assertEqual(log.getvalue(), b"STEP 12 epoch=2 loss=1\n")
        self.assertTrue(self.children[-1].stdout.closed)

    def test_early_exit_does_not_claim_interruption(self):
        self.assertEqual(self.execute("pass", io.BytesIO()), (False, 0))

    def test_keyboard_interruption_reaps_the_child(self):
        with patch.object(proof.selectors, "DefaultSelector") as selector:
            selector.return_value.__enter__.return_value.select.side_effect = KeyboardInterrupt
            with self.assertRaises(KeyboardInterrupt):
                self.execute("import time; time.sleep(60)", io.BytesIO())
        self.assertEqual(self.children[-1].returncode, -signal.SIGKILL)
        self.assertTrue(self.children[-1].stdout.closed)


class InterruptionReportTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / ".local/runs/source"
        self.continuous = self.root / ".local/runs/continuous"
        self.run = self.root / ".local/runs/proof"
        self.source.mkdir(parents=True)
        for name in ["settings.json", "identity.json", "baseline.json"]:
            (self.source / name).write_text("{}")
        checkpoint = self.source / "checkpoints/epoch-0001"
        checkpoint.mkdir(parents=True)
        files = {}
        for name in [
            "adapters.safetensors",
            "optimizer.safetensors",
            "random.safetensors",
            "adapter_config.json",
            "metrics.json",
        ]:
            (checkpoint / name).write_bytes(b"synthetic fixture")
            files[name] = contract.sha(checkpoint / name)
        contract.write(
            checkpoint / "checkpoint.json",
            {
                "epoch": 1,
                "state": {"epoch": 1, "steps": 3},
                "run_identity": contract.sha(self.source / "identity.json"),
                "baseline_sha256": contract.sha(self.source / "baseline.json"),
                "files": files,
            },
        )
        for patcher in [
            patch.object(proof, "ROOT", self.root),
            patch.object(
                proof,
                "current_identity",
                return_value=(
                    {"max_epochs": 2, "batch_size": 1},
                    {"samples": [{"partition": "train"}] * 3},
                ),
            ),
        ]:
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_both_process_timeouts_leave_a_failed_report_and_checkpoint(self):
        for phase in ["interruption", "resume"]:
            with self.subTest(phase=phase):
                run = self.run.with_name(phase)
                timeout = subprocess.TimeoutExpired(["synthetic-trainer"], 0.1)
                with (
                    patch.object(
                        proof, "interrupt_at_step", return_value=(True, -signal.SIGTERM)
                    ) as interrupt,
                    patch.object(proof.subprocess, "run") as resume,
                    patch.object(proof, "compare") as compare,
                ):
                    (interrupt if phase == "interruption" else resume).side_effect = timeout
                    with self.assertRaises(subprocess.TimeoutExpired):
                        proof.verify(self.source, self.continuous, run, phase_timeout=0.1)
                    compare.assert_not_called()
                    if phase == "resume":
                        self.assertEqual(resume.call_args.kwargs["timeout"], 0.1)
                report = json.loads((run / "interruption.json").read_text())
                self.assertEqual(report["status"], "interrupted-or-failed")
                self.assertEqual(report["error_type"], "TimeoutExpired")
                self.assertEqual(
                    contract.sha(run / "checkpoints/epoch-0001/checkpoint.json"),
                    contract.sha(self.source / "checkpoints/epoch-0001/checkpoint.json"),
                )

    def test_invalid_proof_deadlines_fail_before_creating_a_run(self):
        for timeout in [0, -1, float("nan"), float("inf")]:
            with self.subTest(timeout=timeout), self.assertRaisesRegex(ValueError, "timeout"):
                proof.verify(self.source, self.continuous, self.run, phase_timeout=timeout)
        self.assertFalse(self.run.exists())


if __name__ == "__main__":
    unittest.main()
