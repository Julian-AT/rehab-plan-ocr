"""Compare two fixed ARM64 reciprocal paths on saved first-BatchNorm tensors."""

import argparse
import ctypes
import importlib.metadata
import json
import os
import platform
import shutil
import subprocess
from pathlib import Path

from batchnorm_fma import FLAGS, REPLAY, compile_reference, compiler, measure
from convolution_lowering import ROOT, digest, unchanged, write

FMA = ROOT / ".local/runs/ocr-batchnorm-fma-20260926-s19-001"
FMA_REPORT = "4623f4482967b6b24109d5c825b6252b287df979fbdb195e1b497b212679ece2"
RESEARCH = ROOT / ".local/runs/ocr-eigen-research-20260926-s19-001"
CPP = Path(__file__).with_suffix(".cpp")
MODES = {0: "reciprocal-control", 1: "hardware-division"}
COEFFICIENTS = ["inverse", "adjusted_scale", "mean_inverse", "adjusted_bias"]
RULE = {
    "scope": "Saved first BatchNorm only; synthetic plan-020 date, width 320.",
    "modes": {str(key): value for key, value in MODES.items()},
    "control": "ARM64 square root, reciprocal estimate, exactly two Newton refinements.",
    "candidate": "ARM64 square root, hardware division of one by that square root.",
    "offset": "bias - ((mean * inverse_std) * scale), with separate FP32 operations.",
    "output": "Separate FP32 input * adjusted_scale + adjusted_bias, no contraction.",
    "gate": "Control must byte-match all three saved affine coefficients and both saved outputs.",
    "rounding": "FE_TONEAREST, no FP32 flushing, finite normal-or-zero operands.",
    "rtol": 1e-3,
    "atol": 1e-5,
    "stop": "Any failed control; no coefficient search, epsilon change or model rewrite.",
    "qualified": False,
}


def load_reference(path):
    function = ctypes.CDLL(str(path)).batchnorm_reciprocal
    function.argtypes = [ctypes.POINTER(ctypes.c_float)] * 5 + [
        ctypes.c_float,
        ctypes.c_size_t,
        ctypes.c_size_t,
        ctypes.c_int,
        ctypes.POINTER(ctypes.c_float),
        ctypes.POINTER(ctypes.c_float),
    ]
    function.restype = ctypes.c_int
    return function


def machine():
    if platform.machine() not in {"arm64", "aarch64"}:
        raise ValueError("This instruction-level diagnostic requires native ARM64")
    return {
        "architecture": platform.machine(),
        "system": platform.platform(),
        "compiler": subprocess.check_output([*compiler(), "--version"], text=True),
    }


def prepare(output):
    identity = machine()
    if digest(FMA / "report.json") != FMA_REPORT:
        raise ValueError("Retained contraction report changed")
    report = json.loads((FMA / "report.json").read_text())
    previous = json.loads((FMA / "protocol.json").read_text())
    if not (
        report["controls_valid"]
        and report["sources_unchanged"]
        and report["protocol_sha256"] == digest(FMA / "protocol.json")
        and report["outputs_sha256"] == digest(FMA / "outputs.npz")
    ):
        raise ValueError("Saved coefficient controls or identities disagree")
    sources = dict(previous["sources"])
    provenance = []
    for name in ["sources.json", "ort-sources.json"]:
        for row in json.loads((RESEARCH / name).read_text()):
            sources[str(RESEARCH / row["path"])] = row["sha256"]
            provenance.append(row)
    for name in ["native-disassembly.json", "ort-native-disassembly.json"]:
        metadata = json.loads((RESEARCH / name).read_text())
        sources[str(ROOT / metadata["command"][-1])] = metadata["binary_sha256"]
    native = json.loads((RESEARCH / "native-disassembly.json").read_text())
    receipt = json.loads((RESEARCH / "disassembly-retention.json").read_text())
    sources[str(RESEARCH / "native-batchnorm.asm")] = native["assembly_sha256"]
    sources[str(RESEARCH / "ort-batchnorm-function.asm")] = receipt["function_sha256"]
    unchanged(sources)
    # Preserve the bounded listings and the separate receipt for the removed full listing.
    for path in [
        FMA / "report.json",
        FMA / "protocol.json",
        FMA / "outputs.npz",
        Path(__file__).resolve(),
        CPP,
        Path(__file__).parent / "tests/test-batchnorm-reciprocal.py",
        *[
            RESEARCH / name
            for name in [
                "sources.json",
                "ort-sources.json",
                "native-disassembly.json",
                "native-batchnorm.asm",
                "ort-native-disassembly.json",
                "ort-batchnorm-function.asm",
                "disassembly-retention.json",
                "findings.md",
            ]
        ],
    ]:
        sources[str(path)] = digest(path)
    unchanged(sources)
    description = ROOT / "ml/experiments/2026-09-26-s19-ocr-batchnorm-reciprocal.md"
    output.mkdir(parents=True, mode=0o700, exist_ok=False)
    write(
        output / "protocol.json",
        {
            "rule": RULE,
            "sources": sources,
            "provenance": provenance,
            "packages": previous["packages"],
            "machine": identity,
            "flags": FLAGS,
            "description": {
                "path": str(description.relative_to(ROOT)),
                "sha256": digest(description),
                "text": description.read_text(),
            },
            "makefile_sha256_at_preparation": digest(ROOT / "Makefile"),
        },
    )
    print("Prepared two source-derived reciprocal paths; no tensor execution.")


def execute(output):
    import numpy as np
    import onnx

    protocol = json.loads((output / "protocol.json").read_text())
    if (
        protocol["rule"] != RULE
        or protocol["flags"] != FLAGS
        or protocol["machine"] != machine()
        or any(
            importlib.metadata.version(name) != value
            for name, value in protocol["packages"].items()
        )
    ):
        raise ValueError("Prepared arithmetic contract, machine or packages changed")
    sources = protocol["sources"] | {
        str(output / "protocol.json"): digest(output / "protocol.json")
    }
    unchanged(sources)
    if {path.name for path in output.iterdir()} != {"protocol.json"}:
        raise ValueError("Execution requires the untouched prepared directory")
    with (output / "execution.json").open("x") as stream:
        json.dump({"pid": os.getpid(), "protocol_sha256": digest(output / "protocol.json")}, stream)
    report = {
        "qualified": False,
        "full_corpus_started": False,
        "controls_valid": False,
        "protocol_sha256": digest(output / "protocol.json"),
    }
    outputs = {}
    try:
        with np.load(REPLAY / "same-input.npz", allow_pickle=False) as saved:
            arrays = {key: saved[key].copy() for key in saved.files}
        with np.load(FMA / "outputs.npz", allow_pickle=False) as saved:
            previous = {key: saved[key].copy() for key in saved.files}
        operand = arrays["input"]
        if operand.dtype != np.float32 or operand.shape != (1, 48, 24, 160):
            raise ValueError("The fixed input shape or datatype changed")
        graph = onnx.load(REPLAY / "paddle-expression.onnx")
        epsilon = onnx.numpy_helper.to_array(
            next(value for value in graph.graph.initializer if value.name == "epsilon")
        )
        if epsilon.shape != () or epsilon.dtype != np.float32:
            raise ValueError("The saved epsilon must remain scalar FP32")
        report["epsilon_bytes"] = epsilon.tobytes().hex()
        values = [
            np.ascontiguousarray(arrays[name])
            for name in ["input", "scale", "bias", "mean", "variance"]
        ]
        if any(value.shape != (48,) for value in values[1:]):
            raise ValueError("Each parameter must contain exactly 48 channels")
        if any(value.dtype != np.float32 for value in values):
            raise ValueError("Only unchanged FP32 operands are allowed")
        source_copy = output / CPP.name
        shutil.copy2(CPP, source_copy)
        library = output / (
            "reciprocal.dylib" if platform.system() == "Darwin" else "reciprocal.so"
        )
        report["compile_command"] = compile_reference(library, source_copy)
        report["library_sha256"] = digest(library)
        function = load_reference(library)
        pointers = [value.ctypes.data_as(ctypes.POINTER(ctypes.c_float)) for value in values]
        comparisons = {}
        for mode, name in MODES.items():
            coefficients = np.empty((4, 48), dtype=np.float32)
            actual = np.empty_like(operand)
            code = function(
                *pointers,
                float(epsilon),
                48,
                24 * 160,
                mode,
                coefficients.ctypes.data_as(ctypes.POINTER(ctypes.c_float)),
                actual.ctypes.data_as(ctypes.POINTER(ctypes.c_float)),
            )
            if code:
                raise ValueError("C reference rejected operands, shape or rounding mode")
            outputs[name] = actual
            for key, value in zip(COEFFICIENTS, coefficients, strict=True):
                outputs[f"{name}-{key}"] = value
            if mode == 0:
                controls = {
                    key: measure(previous[key], coefficients[index])
                    for index, key in enumerate(COEFFICIENTS)
                    if index > 0
                }
                controls["retained_expression"] = measure(arrays["paddle_expression"], actual)
                controls["retained_c_output"] = measure(previous["separate-control"], actual)
                report["controls"] = controls
                if not all(value["bitwise_equal"] for value in controls.values()):
                    raise ValueError("Reciprocal control differs from saved coefficients/output")
                report["controls_valid"] = True
            comparisons[name] = {
                "vs_paddle": measure(arrays["paddle"], actual),
                "vs_onnx": measure(arrays["onnx"], actual),
            }
        report["expressions"] = comparisons
        report["status"] = "diagnosed-not-qualified"
    except Exception as error:
        report.update(status="failed-control-or-execution", error=str(error))
        raise
    finally:
        if outputs:
            np.savez_compressed(output / "outputs.npz", **outputs)
            report["outputs_sha256"] = digest(output / "outputs.npz")
        report["sources_unchanged"] = False
        try:
            unchanged(sources)
            report["sources_unchanged"] = True
        finally:
            write(output / "report.json", report)
    print(json.dumps(report, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["prepare", "execute"])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / ".local/runs") or output == ROOT / ".local/runs":
        parser.error("Use a private directory below .local/runs")
    os.umask(0o077)
    (prepare if args.phase == "prepare" else execute)(output)


if __name__ == "__main__":
    main()
