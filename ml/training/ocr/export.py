"""Export the selected adaptation checkpoint and verify the pinned ONNX CPU route."""

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

from contract import sha, write
from run_identity import validate_inputs
from train import ROOT, UPSTREAM, selected_checkpoint


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    run = args.run.resolve()
    output = (args.output or run / "deployment").resolve()
    if not output.is_relative_to(ROOT / ".local"):
        parser.error("Exported artifacts must remain below .local")
    _, identity_verification = validate_inputs(run)
    selected_checkpoint(run)
    subprocess.run(
        [sys.executable, str(Path(__file__).with_name("restore.py")), "--offline"], check=True
    )
    output.mkdir(parents=True, exist_ok=False)
    report = {
        "schema_version": 1,
        "status": "running",
        "qualified": False,
        "selection_sha256": sha(run / "selection.json"),
        "run_identity_sha256": sha(run / "identity.json"),
        "identity_verification": identity_verification,
        "source_sha256": sha(Path(__file__)),
        "parity_source_sha256": sha(ROOT / "ml/evaluation/recognition/export_parity.py"),
        "stages": [],
    }
    commands = [
        (
            "export",
            [
                sys.executable,
                "tools/export_model.py",
                "-c",
                str(run / "export.yml"),
                "-o",
                f"Global.pretrained_model={run}/selected.pdparams",
                f"Global.save_inference_dir={output}/paddle",
            ],
        ),
        (
            "onnx",
            [
                str(Path(sys.executable).with_name("paddle2onnx")),
                "--model_dir",
                str(output / "paddle"),
                "--model_filename",
                "inference.json",
                "--params_filename",
                "inference.pdiparams",
                "--save_file",
                str(output / "recognizer.onnx"),
                "--opset_version",
                "17",
                "--enable_auto_update_opset",
                "False",
                "--optimize_tool",
                "None",
            ],
        ),
        (
            "parity",
            [
                sys.executable,
                str(ROOT / "ml/evaluation/recognition/export_parity.py"),
                "--run",
                str(run),
                "--onnx",
                str(output / "recognizer.onnx"),
                "--report",
                str(output / "parity.json"),
            ],
        ),
    ]
    try:
        for name, command in commands:
            stage = {"name": name, "command": command, "started": time.time(), "status": "running"}
            report["stages"].append(stage)
            write(output / "export.json", report)
            with (output / f"{name}.log").open("w") as log:
                subprocess.run(
                    command, cwd=UPSTREAM, stdout=log, stderr=subprocess.STDOUT, check=True
                )
            stage.update(status="passed", elapsed_seconds=time.time() - stage["started"])
            write(output / "export.json", report)
        report.update(
            status="desktop-parity-passed", artifact_sha256=sha(output / "recognizer.onnx")
        )
    except BaseException as error:
        report["status"] = "interrupted-or-failed"
        if report["stages"]:
            report["stages"][-1].update(
                status="failed",
                elapsed_seconds=time.time() - report["stages"][-1]["started"],
                error_type=type(error).__name__,
                exit_code=getattr(error, "returncode", None),
            )
        write(output / "export.json", report)
        raise
    write(output / "export.json", report)
    print(json.dumps({"status": report["status"], "qualified": False}))


if __name__ == "__main__":
    for name in ["OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"]:
        os.environ.setdefault(name, "2")
    main()
