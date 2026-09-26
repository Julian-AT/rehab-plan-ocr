"""Convert pinned Paddle weights and smoke-test the two local region readers.

Run with the pinned llama.cpp converter requirements. Compatibility is a loading
and invented-image check, never accuracy or permission to package a model.
"""

import argparse
import hashlib
import importlib.metadata
import importlib.util
import json
import platform
import subprocess
import sys
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FONT_PATHS = [
    Path("/System/Library/Fonts/Supplemental/Arial.ttf"),
    Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
]
_source_spec = importlib.util.spec_from_file_location(
    "vlm_download_provenance", Path(__file__).with_name("fetch-vlm.py")
)
_source = importlib.util.module_from_spec(_source_spec)
_source_spec.loader.exec_module(_source)


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def pin_inputs(bindings, paths):
    selected = {}
    for path in paths:
        key = str(path.absolute())
        actual = sha(path)
        if key in bindings and bindings[key] != actual:
            raise ValueError(f"Qualification input changed: {path}")
        bindings[key] = actual
        selected[key] = actual
    return selected


def verify_inputs(bindings):
    for path, expected in bindings.items():
        try:
            if sha(path) == expected:
                continue
        except OSError:
            pass
        raise ValueError(f"Qualification input changed: {path}")


def checked_run(command, bindings, **kwargs):
    try:
        return subprocess.run(command, **kwargs)
    finally:
        verify_inputs(bindings)


@contextmanager
def evidence(output, result, bindings, runtime, revision):
    try:
        try:
            yield
        finally:
            verify_inputs(bindings)
            current = subprocess.check_output(
                ["git", "-C", str(runtime), "rev-parse", "HEAD"], text=True
            ).strip()
            dirty = subprocess.check_output(
                ["git", "-C", str(runtime), "status", "--porcelain"], text=True
            ).strip()
            if current != revision or dirty:
                raise ValueError("Pinned converter checkout changed during qualification")
        result["status"] = "completed"
    except BaseException as error:
        result.update(status="failed", error=f"{type(error).__name__}: {error}")
        for candidate in result["candidates"]:
            candidate["compatible"] = False
        raise
    finally:
        result["bound_inputs_sha256"] = bindings
        with (output / "candidates.json").open("x") as manifest:
            manifest.write(json.dumps(result, indent=2) + "\n")


def qualify(args):
    if args.output.exists() or args.output.is_symlink():
        raise ValueError(
            "Use a new output directory; existing conversion and review evidence is preserved."
        )
    lock_path = ROOT / "ml/registry/runtime/vlm-experiments.lock.json"
    lock_bytes = lock_path.read_bytes()
    lock = json.loads(lock_bytes)
    bindings = {str(lock_path.absolute()): hashlib.sha256(lock_bytes).hexdigest()}
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
    source_manifests = {}
    for candidate in lock["candidates"]:
        source_hashes[candidate["id"]] = _source.verify_candidate(
            sources[candidate["id"]], candidate
        )
        for item in source_hashes[candidate["id"]]:
            bindings[str((sources[candidate["id"]] / item["path"]).absolute())] = item["sha256"]
        manifest = sources[candidate["id"]] / "source-manifest.json"
        if manifest.is_file():
            source_manifests[candidate["id"]] = {
                "path": str(manifest.resolve()),
                "sha256": sha(manifest),
            }
            bindings[str(manifest.absolute())] = source_manifests[candidate["id"]]["sha256"]
    converter = args.runtime / "convert_hf_to_gguf.py"
    pin_inputs(bindings, [converter, args.binary, Path(__file__).with_name("fetch-vlm.py")])
    output = args.output
    output.mkdir(parents=True, exist_ok=False)
    result = {"schema_version": 1, "candidates": [], "packaging_eligible": False}
    with evidence(output, result, bindings, args.runtime, revision):
        convert_and_measure(
            args, converter, revision, source_hashes, source_manifests, bindings, result
        )
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


def convert_and_measure(
    args, converter, revision, source_hashes, source_manifests, bindings, result
):
    output = args.output
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
            checked_run(
                command,
                bindings,
                check=True,
                stdout=log,
                stderr=log,
                env={
                    **__import__("os").environ,
                    "HF_HUB_OFFLINE": "1",
                    "TRANSFORMERS_OFFLINE": "1",
                },
            )
        pin_inputs(bindings, [path])
    candidates = [
        ("glm-ocr", args.glm / "GLM-OCR-Q8_0.gguf", args.glm / "mmproj-GLM-OCR-Q8_0.gguf"),
        ("paddleocr-vl-1.6", text, projector),
    ]
    from PIL import Image, ImageDraw, ImageFont

    check = output / "compatibility"
    check.mkdir(exist_ok=True)
    font = next(p for p in FONT_PATHS if p.is_file())
    pin_inputs(bindings, [font])
    image = Image.new("RGB", (800, 120), "white")
    expected = "08:00 - 08:30 Bewegung Raum 2"
    ImageDraw.Draw(image).text(
        (30, 35), expected, fill="black", font=ImageFont.truetype(str(font), 36)
    )
    image.save(check / "synthetic.png")
    pin_inputs(bindings, [check / "synthetic.png", font])
    result.update(
        {
            "schema_version": 1,
            "binary": str(args.binary.resolve()),
            "binary_sha256": bindings[str(args.binary.absolute())],
            "runtime_revision": revision,
            "lock_sha256": bindings[
                str((ROOT / "ml/registry/runtime/vlm-experiments.lock.json").absolute())
            ],
            "converter_sha256": bindings[str(converter.absolute())],
            "converter_commands": converter_commands,
            "source_files": source_hashes,
            "source_manifests": source_manifests,
            "source_verifier_sha256": sha(Path(__file__).with_name("fetch-vlm.py")),
            "conversion_environment": {
                name: importlib.metadata.version(name)
                for name in ["torch", "transformers", "numpy", "sentencepiece", "protobuf"]
            },
            "candidates": [],
            "packaging_eligible": False,
        }
    )
    for family, model, projection in candidates:
        measured = pin_inputs(bindings, [model, projection, check / "synthetic.png", args.binary])
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
            raw = path.read_bytes()
            bindings[str(path.absolute())] = hashlib.sha256(raw).hexdigest()
            status = json.loads(raw)
        except (subprocess.SubprocessError, OSError, ValueError):
            pass
        finally:
            # Integrity failures must escape the ordinary incompatible-reader fallback.
            verify_inputs(measured)
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
                "model_sha256": measured[str(model.absolute())],
                "projector_sha256": measured[str(projection.absolute())],
                "compatible": compatible,
                "smoke_sha256": bindings.get(str(path.absolute())),
                "smoke_input_sha256": measured[str((check / "synthetic.png").absolute())],
                "packaging_eligible": False,
            }
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
