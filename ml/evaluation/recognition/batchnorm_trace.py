"""Locate the first remaining mapped difference in a retained corrected OCR graph."""

import argparse
import copy
import gc
import importlib.metadata
import json
import os
import shutil
import tempfile
from pathlib import Path

from batchnorm_fma import measure
from batchnorm_onnx import session
from batchnorm_reciprocal import machine
from convolution_lowering import ROOT, digest, unchanged, write
from convolution_trace import trace_conclusion
from operation_parity import instrument_pir

STAGE = ROOT / ".local/runs/ocr-batchnorm-stage-20260926-s19-001"
REPORT = "46644e38da56f3758d58367fb9e0bd03390d31dd791993ae116ce2f3a31b9590"
VARIANT = "division-convolution-ORT_DISABLE_ALL"
RULE = {
    "selection": "First failed division-convolution ORT_DISABLE_ALL case in the unchanged twelve-case order.",
    "controls": "Reproduce saved input, dynamic-Paddle output with unfused static Paddle, original and candidate bytes before tracing.",
    "trace": "Retained corrected graph and copied unfused PIR, ORT_DISABLE_ALL, 16 mapped outputs per batch.",
    "stop": "First batch with a byte difference, or any changed final-output control.",
    "equality": "Same shape, dtype and C-order bytes; signed zero is distinguished.",
    "rtol": 1e-3,
    "atol": 1e-5,
    "batch_size": 16,
    "qualified": False,
    "full_corpus_automatic": False,
}


def select_case(previous, report):
    expected = [
        (entry["role"], case["id"], case["width"])
        for entry in previous["runs"]
        for case in entry["cases"]
    ]
    actual = [(row["role"], row["id"], row["width"]) for row in report["cases"]]
    if (
        len(expected) != 12
        or len(set(expected)) != 12
        or actual != expected
        or report.get("controls_valid") is not True
        or report.get("sources_unchanged") is not True
        or report.get("selected_for_full_corpus") is not None
        or not all(row["original_control_reproduced"] for row in report["cases"])
        or not all(
            row["variants"][VARIANT]["reload_bitwise_equal"] is True for row in report["cases"]
        )
    ):
        raise ValueError("Expected all twelve unchanged failed-stage controls")
    for row in report["cases"]:
        variant = row["variants"][VARIANT]
        if variant["reload_bitwise_equal"] is not True:
            raise ValueError("Candidate serialization control failed")
        if variant["allclose"] is not True or variant["same_tokens"] is not True:
            entry = next(run for run in previous["runs"] if run["role"] == row["role"])
            index = next(
                i
                for i, case in enumerate(entry["cases"])
                if (case["id"], case["width"]) == (row["id"], row["width"])
            )
            return entry, index, row
    raise ValueError("No remaining candidate failure")


def prepare(output):
    previous = json.loads((STAGE / "protocol.json").read_text())
    report = json.loads((STAGE / "report.json").read_text())
    if digest(STAGE / "report.json") != REPORT or report["protocol_sha256"] != digest(
        STAGE / "protocol.json"
    ):
        raise ValueError("Frozen full-graph experiment changed")
    entry, index, row = select_case(previous, report)
    directory = STAGE / entry["role"]
    candidate = directory / "division-convolution.onnx"
    arrays = directory / f"{VARIANT}-{index}.npz"
    control = directory / f"control-{index}.npz"
    sources = dict(previous["sources"])
    for path in [candidate, arrays, control]:
        if digest(path) != report["artifacts"][str(path.relative_to(STAGE))]:
            raise ValueError("Retained graph or output identity changed")
    for path in [
        STAGE / "protocol.json",
        STAGE / "report.json",
        candidate,
        arrays,
        control,
        Path(__file__).resolve(),
        Path(__file__).parent / "tests/test-batchnorm-trace.py",
    ]:
        sources[str(path)] = digest(path)
    unchanged(sources)
    output.mkdir(parents=True, mode=0o700, exist_ok=False)
    write(
        output / "protocol.json",
        {
            "rule": RULE,
            "sources": sources,
            "run": entry["run"],
            "unfused": entry["unfused"],
            "case": entry["cases"][index],
            "previous": row,
            "candidate": str(candidate),
            "control_arrays": str(control),
            "candidate_arrays": str(arrays),
            "packages": previous["packages"],
            "machine": machine(),
            "description": (
                ROOT / "ml/experiments/2026-09-26-s20-ocr-batchnorm-trace.md"
            ).read_text(),
        },
    )
    print("Prepared one retained failure; no model inference or deployment change.")


def trace(output, protocol, report):
    import numpy as np
    import onnx
    import paddle
    from export_parity import normalized_image

    pixels = normalized_image(protocol["case"]["image"], protocol["case"]["width"])
    with np.load(protocol["control_arrays"], allow_pickle=False) as values:
        saved = {name: values[name].copy() for name in values.files}
    with np.load(protocol["candidate_arrays"], allow_pickle=False) as values:
        candidate_output = values["candidate"].copy()
    unfused = Path(protocol["unfused"])
    graph = onnx.load(protocol["candidate"])
    paddle.set_device("cpu")
    native = paddle.jit.load(str(unfused / "inference"))
    native.eval()
    with paddle.no_grad():
        native_control = native(paddle.to_tensor(pixels)).numpy()
    del native
    comparisons = {"input": measure(saved["input"], pixels)}
    comparisons["native"] = measure(saved["paddle"], native_control)
    for name, path, level, expected in [
        (
            "original",
            Path(protocol["run"]) / "deployment/recognizer.onnx",
            "ORT_ENABLE_ALL",
            saved["original"],
        ),
        ("candidate", Path(protocol["candidate"]), "ORT_DISABLE_ALL", candidate_output),
    ]:
        runtime = session(onnx.load(path), level)
        actual = runtime.run(None, {runtime.get_inputs()[0].name: pixels})[0]
        comparisons[name] = measure(expected, actual)
        del runtime
    report["original_controls"] = comparisons
    if not all(row["bitwise_equal"] for row in comparisons.values()):
        raise ValueError("Saved complete-output controls did not reproduce")
    original = json.loads((unfused / "inference.json").read_text())
    _, aligned, missing = instrument_pir(
        original, {name for node in graph.graph.node for name in node.output}
    )
    report.update(aligned_outputs=len(aligned), unmapped_float_outputs=missing)
    for start in range(0, len(aligned), RULE["batch_size"]):
        names = {row["onnx_name"] for row in aligned[start : start + RULE["batch_size"]]}
        copied, batch, _ = instrument_pir(original, names)
        with tempfile.TemporaryDirectory(prefix=".trace-", dir=output) as temporary:
            folder = Path(temporary)
            (folder / "inference.json").write_text(json.dumps(copied))
            shutil.copyfile(unfused / "inference.pdiparams", folder / "inference.pdiparams")
            observed = copy.deepcopy(graph)
            for row in batch:
                observed.graph.output.append(
                    onnx.helper.make_tensor_value_info(
                        row["onnx_name"], onnx.TensorProto.FLOAT, None
                    )
                )
            runtime = session(observed, "ORT_DISABLE_ALL")
            native = paddle.jit.load(str(folder / "inference"))
            native.eval()
            with paddle.no_grad():
                expected = [value.numpy() for value in native(paddle.to_tensor(pixels))]
            actual = runtime.run(None, {runtime.get_inputs()[0].name: pixels})
            if len(expected) != len(batch) + 1 or len(actual) != len(expected):
                raise ValueError("Instrumented output alignment changed")
            controls = {
                "native": measure(native_control, expected[0]),
                "candidate": measure(candidate_output, actual[0]),
            }
            valid = all(item["bitwise_equal"] for item in controls.values())
            report["batches"].append({"start": start, "count": len(batch), "controls": controls})
            for row, left, right in zip(batch, expected[1:], actual[1:], strict=True):
                report["operations"].append({**row, **measure(left, right)})
            conclusion = trace_conclusion(report["operations"], missing, valid)
            if not valid or conclusion["first_mapped_difference"]:
                # Keep the entire first differing/perturbed batch, including its
                # final controls. These are development failure fixtures only.
                fixture = output / "stopping-batch.npz"
                np.savez_compressed(
                    fixture,
                    input=pixels,
                    **{f"paddle_{i}": value for i, value in enumerate(expected)},
                    **{f"onnx_{i}": value for i, value in enumerate(actual)},
                )
                onnx.save(observed, output / "stopping-batch.onnx")
                (output / "stopping-batch.pir.json").write_text(json.dumps(copied))
                for path in output.glob("stopping-batch.*"):
                    report["artifacts"][path.name] = digest(path)
            del native, runtime, observed, expected, actual
            gc.collect()
        report.update(conclusion)
        print(f"Traced {len(report['operations'])}/{len(aligned)} mapped outputs", flush=True)
        if not valid or conclusion["first_mapped_difference"]:
            break
    report["status"] = "diagnosed-not-qualified" if valid else "instrumentation-perturbs-output"


def execute(output):
    protocol = json.loads((output / "protocol.json").read_text())
    if (
        protocol["rule"] != RULE
        or protocol["machine"] != machine()
        or any(
            importlib.metadata.version(name) != value
            for name, value in protocol["packages"].items()
        )
    ):
        raise ValueError("Prepared protocol, machine or runtime changed")
    sources = protocol["sources"] | {
        str(output / "protocol.json"): digest(output / "protocol.json")
    }
    unchanged(sources)
    if {path.name for path in output.iterdir()} != {"protocol.json"}:
        raise ValueError("Execution needs the untouched prepared directory")
    write(output / "execution.json", {"pid": os.getpid()})
    report = {
        "protocol_sha256": digest(output / "protocol.json"),
        "qualified": False,
        "full_corpus_started": False,
        "controls_valid": False,
        "artifacts": {},
        "batches": [],
        "operations": [],
    }
    try:
        trace(output, protocol, report)
    except BaseException as error:
        report.update(
            status="failed-control-or-execution", error_type=type(error).__name__, error=str(error)
        )
        raise
    finally:
        report["sources_unchanged"] = False
        try:
            unchanged(sources)
            unchanged({str(output / name): value for name, value in report["artifacts"].items()})
            report["sources_unchanged"] = True
        finally:
            write(output / "report.json", report)
    print(json.dumps({key: report[key] for key in ["status", "controls_valid", "qualified"]}))


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
    for variable in ["OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"]:
        os.environ.setdefault(variable, "2")
    main()
