"""Test fixed FP32 contraction hypotheses on the retained first BatchNorm only."""

import argparse
import ctypes
import importlib.metadata
import json
import os
import platform
import shutil
import subprocess
from pathlib import Path

from convolution_lowering import ROOT, digest, unchanged, write
from operation_parity import compare

REPLAY = ROOT / ".local/runs/ocr-batchnorm-replay-20260926-s19-001"
REPORT = "d653d35a8e439e907bf0b22754ee5190a90c30ec197c89f20577a7cc2a8bec9f"
CPP = Path(__file__).with_suffix(".cpp")
FLAGS = ["-std=c++17", "-O2", "-fno-fast-math", "-ffp-contract=off", "-shared", "-fPIC"]
MODES = {0: "separate-control", 1: "fused-output", 2: "fused-offset", 3: "both-fused"}
RULE = {
    "scope": "Same frozen plan-020 date crop, width 320, first BatchNorm only.",
    "coefficients": "Retained Paddle-grouping graph exposes unchanged FP32 affine coefficients.",
    "controls": "Instrumented output equals retained expression; C separate output equals it bitwise.",
    "hypotheses": MODES,
    "offset": "fma(-mean_times_inverse, scale, bias)",
    "output": "fma(input, adjusted_scale, adjusted_bias)",
    "rounding": "FE_TONEAREST, finite normal-or-zero inputs, explicit FP32 fma only.",
    "rtol": 1e-3,
    "atol": 1e-5,
    "stop": "Any control mismatch; no coefficient search, model rewrite or full-corpus run.",
    "qualified": False,
}
# JSON keys have string identities; use the serialized form in the frozen rule.
RULE["hypotheses"] = {str(key): value for key, value in MODES.items()}


def measure(expected, actual):
    result = compare(expected, actual)
    result["bitwise_equal"] = expected.tobytes() == actual.tobytes()
    return result


def compiler():
    return ["xcrun", "clang++"] if platform.system() == "Darwin" else ["clang++"]


def compile_reference(destination, source=CPP):
    command = [*compiler(), *FLAGS, str(source), "-o", str(destination), "-lm"]
    subprocess.run(command, check=True, capture_output=True, text=True)
    return command


def load_reference(path):
    function = ctypes.CDLL(str(path)).batchnorm_affine
    function.argtypes = [ctypes.POINTER(ctypes.c_float)] * 6 + [
        ctypes.c_size_t,
        ctypes.c_size_t,
        ctypes.c_int,
        ctypes.POINTER(ctypes.c_float),
    ]
    function.restype = ctypes.c_int
    return function


def prepare(output):
    if digest(REPLAY / "report.json") != REPORT:
        raise ValueError("Retained replay report changed")
    report = json.loads((REPLAY / "report.json").read_text())
    previous = json.loads((REPLAY / "protocol.json").read_text())
    if not (
        report["controls_valid"]
        and report["parameters_bitwise_equal"]
        and report["sources_unchanged"]
    ):
        raise ValueError("The retained same-input controls did not pass")
    if report["protocol_sha256"] != digest(REPLAY / "protocol.json"):
        raise ValueError("Retained replay protocol changed")
    for name, expected in report["artifacts"].items():
        if digest(REPLAY / name) != expected:
            raise ValueError("Retained replay artifact changed")
    sources = previous["sources"] | {
        str(path): digest(path)
        for path in [
            REPLAY / "report.json",
            REPLAY / "protocol.json",
            REPLAY / "same-input.npz",
            REPLAY / "paddle-expression.onnx",
            Path(__file__).resolve(),
            CPP,
            Path(__file__).with_name("convolution_lowering.py"),
            Path(__file__).with_name("operation_parity.py"),
        ]
    }
    unchanged(sources)
    output.mkdir(parents=True, mode=0o700, exist_ok=False)
    write(
        output / "protocol.json",
        {
            "rule": RULE,
            "sources": sources,
            "packages": previous["trace"]["packages"],
            "compiler": subprocess.check_output([*compiler(), "--version"], text=True),
            "flags": FLAGS,
        },
    )
    print("Prepared explicit contraction hypotheses; no inference or model change.")


def execute(output):
    import numpy as np
    import onnx
    import onnxruntime as ort

    protocol = json.loads((output / "protocol.json").read_text())
    if (
        protocol["rule"] != RULE
        or protocol["flags"] != FLAGS
        or any(
            importlib.metadata.version(name) != value
            for name, value in protocol["packages"].items()
        )
        or protocol["compiler"] != subprocess.check_output([*compiler(), "--version"], text=True)
    ):
        raise ValueError("Prepared arithmetic contract, compiler or runtime changed")
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
    try:
        with np.load(REPLAY / "same-input.npz", allow_pickle=False) as saved:
            arrays = {key: saved[key].copy() for key in saved.files}
        operand = arrays["input"]
        if operand.dtype != np.float32 or operand.shape != (1, 48, 24, 160):
            raise ValueError("The fixed input shape or datatype changed")
        graph = onnx.load(REPLAY / "paddle-expression.onnx")
        for name in ["new_scale", "new_bias", "mean_inv"]:
            graph.graph.output.append(
                onnx.helper.make_tensor_value_info(name, onnx.TensorProto.FLOAT, [48])
            )
        onnx.checker.check_model(graph)
        options = ort.SessionOptions()
        options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_DISABLE_ALL
        options.intra_op_num_threads, options.inter_op_num_threads = 2, 1
        session = ort.InferenceSession(
            graph.SerializeToString(), sess_options=options, providers=["CPUExecutionProvider"]
        )
        replay, adjusted_scale, adjusted_bias, mean_inverse = session.run(None, {"input": operand})
        report["expression_control"] = measure(arrays["paddle_expression"], replay)
        if not report["expression_control"]["bitwise_equal"]:
            raise ValueError("Exposing coefficients changed the retained expression")
        values = [
            np.ascontiguousarray(v)
            for v in [
                operand,
                adjusted_scale,
                adjusted_bias,
                mean_inverse,
                arrays["scale"],
                arrays["bias"],
            ]
        ]
        if any(v.shape != (48,) for v in values[1:]):
            raise ValueError("Each affine coefficient must contain exactly 48 channels")
        if any(
            v.dtype != np.float32
            or not np.isfinite(v).all()
            or ((np.abs(v) > 0) & (np.abs(v) < np.finfo(np.float32).tiny)).any()
            for v in values
        ):
            raise ValueError("Only finite normal-or-zero FP32 operands are supported")
        source_copy = output / CPP.name
        shutil.copy2(CPP, source_copy)
        library = output / ("affine.dylib" if platform.system() == "Darwin" else "affine.so")
        report["compile_command"] = compile_reference(library, source_copy)
        report["library_sha256"] = digest(library)
        affine = load_reference(library)
        pointers = [v.ctypes.data_as(ctypes.POINTER(ctypes.c_float)) for v in values]
        outputs = {
            "adjusted_scale": adjusted_scale,
            "adjusted_bias": adjusted_bias,
            "mean_inverse": mean_inverse,
        }
        comparisons = {}
        for mode, name in MODES.items():
            actual = np.empty_like(operand)
            code = affine(
                *pointers, 48, 24 * 160, mode, actual.ctypes.data_as(ctypes.POINTER(ctypes.c_float))
            )
            if code:
                raise ValueError("C reference rejected operands or rounding mode")
            outputs[name] = actual
            if mode == 0:
                report["separate_control"] = measure(replay, actual)
                if not report["separate_control"]["bitwise_equal"]:
                    raise ValueError(
                        "Uncontracted C affine output differs from retained arithmetic"
                    )
                report["controls_valid"] = True
            comparisons[name] = {
                "vs_paddle": measure(arrays["paddle"], actual),
                "vs_onnx": measure(arrays["onnx"], actual),
            }
        report["expressions"] = comparisons
        np.savez_compressed(output / "outputs.npz", **outputs)
        report["outputs_sha256"] = digest(output / "outputs.npz")
        report["status"] = "diagnosed-not-qualified"
    except Exception as error:
        report.update(status="failed-control-or-execution", error=str(error))
        raise
    finally:
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
