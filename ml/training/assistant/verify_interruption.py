"""Kill our own development trainer mid-epoch, resume, and compare complete state."""

import argparse
import json
import math
import os
import selectors
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from ml.training.assistant.contract import sha, write  # noqa: E402
from ml.training.assistant.train import current_identity, verify_checkpoint  # noqa: E402
from ml.training.assistant.verify_resume import compare  # noqa: E402


def interrupt_at_step(command, log, environment, trigger, timeout):
    """Bound the proof even when the child is silent or writes an incomplete line."""
    process = subprocess.Popen(
        command, cwd=ROOT, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    deadline = time.monotonic() + timeout
    prefix = f"STEP {trigger} epoch=2 ".encode()
    pending, interrupted = b"", False
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while not interrupted:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise subprocess.TimeoutExpired(command, timeout)
                if not selector.select(remaining):
                    continue
                block = os.read(process.stdout.fileno(), 65536)
                if not block:
                    break
                log.write(block)
                log.flush()
                lines = (pending + block).split(b"\n")
                pending = lines.pop()
                if any(line.startswith(prefix) for line in lines):
                    process.send_signal(signal.SIGTERM)
                    interrupted = True
        remaining = 60 if interrupted else max(0, deadline - time.monotonic())
        remainder, _ = process.communicate(timeout=remaining)
        log.write(remainder)
        return interrupted, process.returncode
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=60)
        process.stdout.close()


def verify(source, continuous, run, phase_timeout=1800):
    if not math.isfinite(phase_timeout) or phase_timeout <= 0:
        raise ValueError("Interruption proof requires a finite positive phase timeout")
    settings, data = current_identity(source)
    other_settings, _ = current_identity(continuous)
    if settings != other_settings or settings["max_epochs"] != 2:
        raise ValueError(
            "Use matching two-epoch development runs for this bounded interruption proof"
        )
    if not run.is_relative_to(ROOT / ".local/runs"):
        raise ValueError("Proof copies belong below ignored .local/runs")
    first = source / "checkpoints/epoch-0001"
    receipt = verify_checkpoint(source, first)
    train_count = sum(row["partition"] == "train" for row in data["samples"])
    if train_count <= settings["batch_size"] * 2:
        raise ValueError("At least three training steps per epoch are needed")
    run.mkdir(parents=True, exist_ok=False)
    for name in ["settings.json", "identity.json", "baseline.json"]:
        shutil.copy2(source / name, run / name)
    shutil.copytree(first, run / "checkpoints/epoch-0001")
    checkpoint_hash = sha(run / "checkpoints/epoch-0001/checkpoint.json")
    command = [
        sys.executable,
        str(Path(__file__).with_name("train.py")),
        "resume",
        "--run",
        str(run),
    ]
    environment = dict(os.environ, HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1")
    trigger = receipt["state"]["steps"] + 2
    report = {
        "schema_version": 1,
        "kind": "sigterm-during-second-epoch",
        "qualified": False,
        "source": str(source.relative_to(ROOT)),
        "continuous": str(continuous.relative_to(ROOT)),
        "source_checkpoint_sha256": checkpoint_hash,
        "runner_sha256": sha(Path(__file__)),
        "signal": "SIGTERM",
        "trigger_step": trigger,
        "phase_timeout_seconds": phase_timeout,
        "status": "running",
    }
    write(run / "interruption.json", report)
    try:
        with (run / "interrupted.log").open("wb") as log:
            interrupted, returncode = interrupt_at_step(
                command, log, environment, trigger, phase_timeout
            )
        report.update(interrupted=interrupted, returncode=returncode)
        write(run / "interruption.json", report)
        if not interrupted or returncode != -signal.SIGTERM:
            raise ValueError(
                "Trainer did not terminate at the requested in-epoch checkpoint boundary"
            )
        if (run / "checkpoints/epoch-0002").exists() or sha(
            run / "checkpoints/epoch-0001/checkpoint.json"
        ) != checkpoint_hash:
            raise ValueError(
                "Interruption changed the complete checkpoint or happened after epoch publication"
            )
        with (run / "resumed.log").open("w") as log:
            subprocess.run(
                command,
                cwd=ROOT,
                env=environment,
                stdout=log,
                stderr=subprocess.STDOUT,
                check=True,
                timeout=phase_timeout,
            )
        parity = run / "resume-parity.json"
        compare(run, continuous, parity)
        report.update(status="interruption-resume-parity-passed", parity_sha256=sha(parity))
    except BaseException as error:
        report.update(
            status="interrupted-or-failed", error_type=type(error).__name__, error=str(error)
        )
        raise
    finally:
        write(run / "interruption.json", report)
    print(json.dumps(report, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--continuous", type=Path, required=True)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--phase-timeout-seconds", type=float, default=1800)
    args = parser.parse_args()
    verify(
        args.source.resolve(),
        args.continuous.resolve(),
        args.run.resolve(),
        args.phase_timeout_seconds,
    )


if __name__ == "__main__":
    main()
