"""Bounded VLM tool phases with an isolated process group and failure cleanup."""

import fcntl
import math
import os
import signal
import subprocess
import sys
import threading
import time
from contextlib import contextmanager

# Match the existing diagnostic/tool budgets; model reading keeps its own 60s limit.
METADATA_SECONDS = 30
PHASE_SECONDS = 900
CLEANUP_SECONDS = 10
GROUP_ENV = "_REHA_VLM_SUPERVISED_PGID"


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


@contextmanager
def cleanup_signals():
    """A relayed TERM must not interrupt the bounded cleanup already in progress."""
    main_thread = threading.current_thread() is threading.main_thread()
    previous = signal.getsignal(signal.SIGTERM) if main_thread else None
    if main_thread:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
    try:
        yield
    finally:
        if main_thread:
            signal.signal(signal.SIGTERM, previous)


def stop_group(process, *, owns_group=True):
    # Kill the whole group even when the leader already exited: a descendant may
    # still own its pipes or continue a compiler/converter after the wrapper ends.
    try:
        if owns_group:
            os.killpg(process.pid, signal.SIGTERM)
        else:
            process.terminate()
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=CLEANUP_SECONDS)
    except subprocess.TimeoutExpired:
        pass
    finally:
        # Only the outer owner kills the group. Nested helpers share that group,
        # so equal cleanup deadlines cannot strand a separate descendant group.
        try:
            if owns_group:
                os.killpg(process.pid, signal.SIGKILL)
            else:
                process.kill()
        except ProcessLookupError:
            pass


def run(command, *, timeout=PHASE_SECONDS, check=False, capture_output=False, **kwargs):
    deadline(timeout)
    if capture_output:
        if "stdout" in kwargs or "stderr" in kwargs:
            raise ValueError("capture_output cannot be combined with stdout/stderr")
        kwargs.update(stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    group = os.getpgrp()
    nested = os.environ.get(GROUP_ENV) == str(group) and os.getsid(0) == group
    env = dict(os.environ if kwargs.get("env") is None else kwargs["env"])
    if nested:
        env[GROUP_ENV] = str(group)
        arguments = command
    else:
        # The exec shim marks the actual new PGID after setsid, preserving its PID.
        # A wrapper several ordinary children below it can still verify the group.
        env.pop(GROUP_ENV, None)
        arguments = [sys.executable, os.path.abspath(__file__), "_exec", *command]
    kwargs["env"] = env
    with interruption():
        child = subprocess.Popen(arguments, start_new_session=not nested, **kwargs)
        interrupted = True
        try:
            stdout, stderr = child.communicate(timeout=timeout)
            interrupted = False
        finally:
            with cleanup_signals():
                if nested and interrupted:
                    # A nested timeout cancels its containing phase. The outer
                    # owner remains outside this group and performs final KILL.
                    os.killpg(group, signal.SIGTERM)
                stop_group(child, owns_group=not nested)
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


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] != "_exec":
        raise SystemExit("Internal VLM process-group exec entrypoint")
    os.environ[GROUP_ENV] = str(os.getpgrp())
    os.execvpe(sys.argv[2], sys.argv[2:], os.environ)
