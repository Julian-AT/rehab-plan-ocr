"""Real tiny process trees prove VLM deadlines and cancellation without model tools."""

import fcntl
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

import vlm_process


class ProcessBounds(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.pids = self.root / "pids.json"

    def tree(self, leader_exits=False):
        grandchild = (
            "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(60)"
        )
        code = (
            "import os,json,subprocess,sys,time; from pathlib import Path; "
            f"child=subprocess.Popen([sys.executable,'-c',{grandchild!r}]); "
            f"Path({str(self.pids)!r}).write_text(json.dumps([os.getpid(),child.pid])); "
            "print('ready',flush=True); " + ("sys.exit(0)" if leader_exits else "time.sleep(60)")
        )
        return [sys.executable, "-c", code]

    def assert_tree_stopped(self):
        self.assertTrue(self.pids.is_file(), "invented processes must actually have started")
        for pid in json.loads(self.pids.read_text()):
            end = time.monotonic() + 2
            while True:
                status = subprocess.run(
                    ["ps", "-o", "stat=", "-p", str(pid)], capture_output=True, text=True, timeout=1
                ).stdout.strip()
                if not status or status.startswith("Z"):
                    break  # Terminated or waiting for the OS to reap an orphan.
                if time.monotonic() >= end:
                    os.kill(pid, signal.SIGKILL)
                    self.fail(f"invented descendant {pid} remained runnable: {status}")
                time.sleep(0.01)

    def test_timeout_stops_leader_and_sigterm_ignoring_descendant(self):
        started = time.monotonic()
        with self.assertRaises(subprocess.TimeoutExpired):
            vlm_process.run(self.tree(), timeout=1, capture_output=True, text=True)
        self.assertLess(time.monotonic() - started, 4)
        self.assert_tree_stopped()

    def test_exited_leader_cannot_leave_descendant_holding_captured_pipe(self):
        with self.assertRaises(subprocess.TimeoutExpired):
            vlm_process.check_output(self.tree(leader_exits=True), timeout=1)
        self.assert_tree_stopped()

    def wrapper(self):
        code = (
            "import sys; "
            f"sys.path.insert(0,{str(Path(__file__).parent)!r}); "
            "import vlm_process; "
            f"vlm_process.run({self.tree()!r},timeout=60)"
        )
        return [sys.executable, "-c", code]

    def test_sigterm_unwinds_wrapper_and_cleans_its_process_tree(self):
        wrapper = subprocess.Popen(self.wrapper(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            end = time.monotonic() + 5
            while not self.pids.exists() and time.monotonic() < end:
                time.sleep(0.01)
            self.assertTrue(self.pids.exists())
            wrapper.send_signal(signal.SIGTERM)
            _, error = wrapper.communicate(timeout=5)
            self.assertNotEqual(wrapper.returncode, 0)
            self.assertIn(b"interrupted by SIGTERM", error)
            self.assert_tree_stopped()
        finally:
            if wrapper.poll() is None:
                wrapper.kill()
            wrapper.communicate(timeout=5)

    def test_outer_deadline_cleans_nested_wrapper_and_child(self):
        with self.assertRaises(subprocess.TimeoutExpired):
            vlm_process.run(self.wrapper(), timeout=1, capture_output=True)
        self.assert_tree_stopped()

    def test_equal_nested_cleanup_budgets_cannot_orphan_term_ignoring_leaf(self):
        leaf = (
            "import os,json,signal,time; from pathlib import Path; "
            "signal.signal(signal.SIGTERM,signal.SIG_IGN); "
            f"Path({str(self.pids)!r}).write_text(json.dumps([os.getppid(),os.getpid()])); "
            "time.sleep(60)"
        )
        wrapper = (
            "import sys,time; "
            f"sys.path.insert(0,{str(Path(__file__).parent)!r}); "
            "import vlm_process; vlm_process.CLEANUP_SECONDS=0.15; "
            # A small scheduling delay makes the parent's equal-budget race deterministic.
            "original=vlm_process.stop_group; "
            "vlm_process.stop_group=lambda *a,**k:(time.sleep(0.03),original(*a,**k))[-1]; "
            f"vlm_process.run([sys.executable,'-c',{leaf!r}],timeout=60)"
        )
        foreign = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(60)"], start_new_session=True
        )
        try:
            with (
                patch.object(vlm_process, "CLEANUP_SECONDS", 0.15),
                self.assertRaises(subprocess.TimeoutExpired),
            ):
                vlm_process.run([sys.executable, "-c", wrapper], timeout=0.5, capture_output=True)
            self.assertIsNone(foreign.poll(), "an unrelated process group must remain untouched")
            self.assert_tree_stopped()
        finally:
            foreign.kill()
            foreign.wait(timeout=2)

    def test_inner_deadline_reaches_group_owner_through_an_ordinary_parent(self):
        leaf = (
            "import os,json,signal,time; from pathlib import Path; "
            "signal.signal(signal.SIGTERM,signal.SIG_IGN); "
            f"Path({str(self.pids)!r}).write_text(json.dumps([os.getppid(),os.getpid()])); "
            "time.sleep(60)"
        )
        nested = (
            "import sys; "
            f"sys.path.insert(0,{str(Path(__file__).parent)!r}); "
            "import vlm_process; vlm_process.CLEANUP_SECONDS=0.15; "
            f"vlm_process.run([sys.executable,'-c',{leaf!r}],timeout=0.3,env={{}})"
        )
        ordinary = (
            f"import subprocess,sys; subprocess.run([sys.executable,'-c',{nested!r}],check=True)"
        )
        started = time.monotonic()
        with self.assertRaises(subprocess.CalledProcessError):
            vlm_process.run(
                [sys.executable, "-c", ordinary], timeout=5, capture_output=True, check=True
            )
        self.assertLess(time.monotonic() - started, 3)
        self.assert_tree_stopped()

    def test_invalid_deadlines_fail_before_process_creation(self):
        with patch.object(vlm_process.subprocess, "Popen") as launch:
            for value in (0, -1, True, float("nan"), float("inf")):
                with self.subTest(value=value), self.assertRaises(ValueError):
                    vlm_process.run(["not-executed"], timeout=value)
            launch.assert_not_called()

    def test_nonzero_exit_keeps_output_and_does_not_become_success(self):
        with self.assertRaises(subprocess.CalledProcessError) as failure:
            vlm_process.run(
                [
                    sys.executable,
                    "-c",
                    "import sys; print('retained'); print('failure',file=sys.stderr); sys.exit(7)",
                ],
                timeout=2,
                capture_output=True,
                text=True,
                check=True,
            )
        self.assertEqual(failure.exception.returncode, 7)
        self.assertEqual(failure.exception.stdout, "retained\n")
        self.assertEqual(failure.exception.stderr, "failure\n")

    def test_build_lock_wait_is_bounded_without_releasing_another_holder(self):
        lock = self.root / "product.lock"
        with lock.open("a") as first, lock.open("a") as second, lock.open("a") as third:
            fcntl.flock(first, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(TimeoutError):
                with vlm_process.locked(second, timeout=0.05):
                    self.fail("another holder's lock was entered")
            with self.assertRaises(BlockingIOError):
                fcntl.flock(third, fcntl.LOCK_EX | fcntl.LOCK_NB)


if __name__ == "__main__":
    unittest.main()
