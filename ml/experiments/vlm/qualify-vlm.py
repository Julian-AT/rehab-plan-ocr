"""Convert pinned Paddle weights and smoke-test the two local region readers.

Run with the pinned llama.cpp converter requirements. Compatibility is a loading
and invented-image check, never accuracy or permission to package a model.
"""

import argparse
import hashlib
import importlib.metadata
import json
import platform
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def qualify(args):
    if args.output.exists() or args.output.is_symlink():
        raise ValueError(
            "Use a new output directory; existing conversion and review evidence is preserved."
        )
    lock_path = ROOT / "ml/registry/runtime/vlm-experiments.lock.json"
    lock = json.loads(lock_path.read_text())
    revision = subprocess.check_output(
        ["git", "-C", str(args.runtime), "rev-parse", "HEAD"], text=True
    ).strip()
    dirty = subprocess.check_output(
        ["git", "-C", str(args.runtime), "status", "--porcelain"], text=True
    ).strip()
    if revision != lock["runtime"]["revision"] or dirty:
        raise ValueError("Use the pinned clean runtime checkout.")
    sources = {"glm-ocr": args.glm, "paddleocr-vl-1.6": args.paddle}
    source_hashes = {}
    for candidate in lock["candidates"]:
        items = []
        for item in candidate["files"]:
            path = sources[candidate["id"]] / item["path"]
            digest = sha(path)
            if path.stat().st_size != item["bytes"] or (
                item["sha256"] and digest != item["sha256"]
            ):
                raise ValueError("Checkpoint integrity failed: " + item["path"])
            items.append({**item, "sha256": digest})
        source_hashes[candidate["id"]] = items
    output = args.output
    output.mkdir(parents=True, exist_ok=False)
    converter = args.runtime / "convert_hf_to_gguf.py"
    text = output / "paddle-f16.gguf"
    projector = output / "mmproj-paddle-f16.gguf"
    converter_commands = []
    for mmproj, path in [(False, text), (True, projector)]:
        command = [
            sys.executable,
            str(converter),
            str(args.paddle),
            "--outfile",
            str(path),
            "--outtype",
            "f16",
        ]
        if mmproj:
            command += ["--mmproj"]
        converter_commands.append(command)
        with (output / ("convert-projector.log" if mmproj else "convert-text.log")).open(
            "x"
        ) as log:
            subprocess.run(
                command,
                check=True,
                stdout=log,
                stderr=log,
                env={
                    **__import__("os").environ,
                    "HF_HUB_OFFLINE": "1",
                    "TRANSFORMERS_OFFLINE": "1",
                },
            )
    candidates = [
        ("glm-ocr", args.glm / "GLM-OCR-Q8_0.gguf", args.glm / "mmproj-GLM-OCR-Q8_0.gguf"),
        ("paddleocr-vl-1.6", text, projector),
    ]
    from PIL import Image, ImageDraw, ImageFont

    check = output / "compatibility"
    check.mkdir(exist_ok=True)
    font = next(
        p
        for p in [
            Path("/System/Library/Fonts/Supplemental/Arial.ttf"),
            Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
        ]
        if p.is_file()
    )
    image = Image.new("RGB", (800, 120), "white")
    expected = "08:00 - 08:30 Bewegung Raum 2"
    ImageDraw.Draw(image).text(
        (30, 35), expected, fill="black", font=ImageFont.truetype(str(font), 36)
    )
    image.save(check / "synthetic.png")
    result = {
        "schema_version": 1,
        "binary": str(args.binary.resolve()),
        "binary_sha256": sha(args.binary),
        "runtime_revision": revision,
        "lock_sha256": sha(lock_path),
        "converter_sha256": sha(converter),
        "converter_commands": converter_commands,
        "source_files": source_hashes,
        "conversion_environment": {
            name: importlib.metadata.version(name)
            for name in ["torch", "transformers", "numpy", "sentencepiece", "protobuf"]
        },
        "candidates": [],
        "packaging_eligible": False,
    }
    for family, model, projection in candidates:
        path = check / (family + ".json")
        command = [
            str(args.binary),
            str(model),
            str(projection),
            family,
            str(check / "synthetic.png"),
            str(path),
        ]
        if platform.system() == "Darwin":
            command = [
                "/usr/bin/sandbox-exec",
                "-p",
                "(version 1) (allow default) (deny network*)",
                *command,
            ]
        status = None
        try:
            with (check / (family + ".log")).open("w") as log:
                subprocess.run(command, check=True, timeout=60, stdout=log, stderr=log)
            status = json.loads(path.read_text())
        except (subprocess.SubprocessError, OSError, ValueError):
            pass
        compatible = bool(
            status
            and status["status"] == "complete"
            and " ".join(status["text"].split()) == expected
        )
        result["candidates"].append(
            {
                "id": family,
                "model": str(model.resolve()),
                "projector": str(projection.resolve()),
                "model_sha256": sha(model),
                "projector_sha256": sha(projection),
                "compatible": compatible,
                "smoke_sha256": sha(path) if path.exists() else None,
                "smoke_input_sha256": sha(check / "synthetic.png"),
                "packaging_eligible": False,
            }
        )
    (output / "candidates.json").write_text(json.dumps(result, indent=2) + "\n")
    print(
        json.dumps(
            {
                "candidates": [
                    {"id": c["id"], "compatible": c["compatible"]} for c in result["candidates"]
                ],
                "packaging_eligible": False,
            }
        )
    )


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--runtime", type=Path, default=ROOT / ".local/upstream/llama.cpp")
    p.add_argument("--binary", type=Path, required=True)
    p.add_argument(
        "--glm", type=Path, default=ROOT / ".local/models/runtime/experiments/checkpoints/glm-ocr"
    )
    p.add_argument(
        "--paddle",
        type=Path,
        default=ROOT / ".local/models/runtime/experiments/checkpoints/paddleocr-vl-1.6",
    )
    p.add_argument("--output", type=Path, required=True)
    qualify(p.parse_args())
