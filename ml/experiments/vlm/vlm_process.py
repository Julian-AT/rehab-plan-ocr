"""Bounded VLM tool phases with an isolated process group and failure cleanup."""

import fcntl
import math
import os
import signal
import subprocess
import threading
import time
from contextlib import contextmanager

# Match the existing diagnostic/tool budgets; model reading keeps its own 60s limit.
METADATA_SECONDS = 30
PHASE_SECONDS = 900
CLEANUP_SECONDS = 10


def deadline(value):
    if isinstance(value, bool) or not math.isfinite(value) or value <= 0:
        raise ValueError("VLM phase timeout must be finite and positive")
    return value


@contextmanager
def interruption():
    """Let CLI SIGTERM unwind evidence/finally blocks just like Ctrl-C."""
    main_thread = threading.current_thread() is threading.main_thread()
    previous = signal.getsignal(signal.SIGTERM) if main_thread else None

    def terminate(signum, frame):
        raise KeyboardInterrupt("VLM tool interrupted by SIGTERM")

    if main_thread:
        signal.signal(signal.SIGTERM, terminate)
    try:
        yield
    finally:
        if main_thread:
            signal.signal(signal.SIGTERM, previous)


def stop_group(process):
    # Kill the whole group even when the leader already exited: a descendant may
    # still own its pipes or continue a compiler/converter after the wrapper ends.
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=CLEANUP_SECONDS)
    except subprocess.TimeoutExpired:
        pass
    finally:
        # A nested VLM wrapper handles TERM and cleans its own isolated children
        # before exiting. Unresponsive children in this group are then forced out.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def run(command, *, timeout=PHASE_SECONDS, check=False, capture_output=False, **kwargs):
    deadline(timeout)
    if capture_output:
        if "stdout" in kwargs or "stderr" in kwargs:
            raise ValueError("capture_output cannot be combined with stdout/stderr")
        kwargs.update(stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    with interruption():
        child = subprocess.Popen(command, start_new_session=True, **kwargs)
        try:
            stdout, stderr = child.communicate(timeout=timeout)
        finally:
            stop_group(child)
            # The deadline also covers inherited pipes. Once the entire group is
            # killed, draining them is bounded, including on KeyboardInterrupt.
            try:
                child.communicate(timeout=CLEANUP_SECONDS)
            finally:
                for stream in (child.stdout, child.stderr):
                    if stream is not None:
                        stream.close()
                child.wait(timeout=CLEANUP_SECONDS)
    result = subprocess.CompletedProcess(command, child.returncode, stdout, stderr)
    if check:
        result.check_returncode()
    return result


def check_output(command, *, timeout=METADATA_SECONDS, **kwargs):
    return run(command, timeout=timeout, stdout=subprocess.PIPE, check=True, **kwargs).stdout


@contextmanager
def locked(stream, *, timeout=PHASE_SECONDS):
    """Bound only the VLM product lock, without taking the unrelated cleanup lock."""
    end = time.monotonic() + deadline(timeout)
    with interruption():
        while True:
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= end:
                    raise TimeoutError("VLM build product lock deadline exceeded") from None
                time.sleep(min(0.05, max(0, end - time.monotonic())))
        try:
            yield
        finally:
            fcntl.flock(stream, fcntl.LOCK_UN)
