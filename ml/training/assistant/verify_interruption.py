"""Kill our own development trainer mid-epoch, resume, and compare complete state."""

import argparse
import json
import os
import shutil
import signal
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from ml.training.assistant.contract import sha, write  # noqa: E402
from ml.training.assistant.train import current_identity  # noqa: E402
from ml.training.assistant.verify_resume import compare  # noqa: E402


def verify(source, continuous, run):
    settings, data = current_identity(source)
    other_settings, _ = current_identity(continuous)
    if settings != other_settings or settings["max_epochs"] != 2:
        raise ValueError(
            "Use matching two-epoch development runs for this bounded interruption proof"
        )
    if not run.is_relative_to(ROOT / ".local/runs"):
        raise ValueError("Proof copies belong below ignored .local/runs")
    first = source / "checkpoints/epoch-0001"
    receipt = json.loads((first / "checkpoint.json").read_text())
    if receipt["run_identity"] != sha(source / "identity.json") or any(
        sha(first / name) != digest for name, digest in receipt["files"].items()
    ):
        raise ValueError("Starting checkpoint changed")
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
        "status": "running",
    }
    write(run / "interruption.json", report)
    with (run / "interrupted.log").open("w") as log:
        process = subprocess.Popen(
            command,
            cwd=ROOT,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        interrupted = False
        try:
            for line in process.stdout:
                log.write(line)
                log.flush()
                if line.startswith(f"STEP {trigger} epoch=2 "):
                    process.send_signal(signal.SIGTERM)
                    interrupted = True
                    break
            remainder, _ = process.communicate(timeout=60)
            log.write(remainder)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
        report.update(interrupted=interrupted, returncode=process.returncode)
        write(run / "interruption.json", report)
    if not interrupted or process.returncode != -signal.SIGTERM:
        raise ValueError("Trainer did not terminate at the requested in-epoch checkpoint boundary")
    if (run / "checkpoints/epoch-0002").exists() or sha(
        run / "checkpoints/epoch-0001/checkpoint.json"
    ) != checkpoint_hash:
        raise ValueError(
            "Interruption changed the complete checkpoint or happened after epoch publication"
        )
    with (run / "resumed.log").open("w") as log:
        subprocess.run(
            command, cwd=ROOT, env=environment, stdout=log, stderr=subprocess.STDOUT, check=True
        )
    parity = run / "resume-parity.json"
    compare(run, continuous, parity)
    report.update(status="interruption-resume-parity-passed", parity_sha256=sha(parity))
    write(run / "interruption.json", report)
    print(json.dumps(report, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--continuous", type=Path, required=True)
    parser.add_argument("--run", type=Path, required=True)
    args = parser.parse_args()
    verify(args.source.resolve(), args.continuous.resolve(), args.run.resolve())


if __name__ == "__main__":
    main()
