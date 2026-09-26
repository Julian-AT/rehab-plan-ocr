"""Trace the retained failed convolution candidate without modifying or promoting it."""

import argparse
import copy
import gc
import importlib.metadata
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

from convolution_lowering import ROOT, digest, unchanged, write
from operation_parity import compare, first_differences, instrument_pir

STAGE = ROOT / ".local/runs/ocr-convolution-stage-20260926-s18-001"
STAGE_REPORT = "e59c054bd2817c40b315f3bb3243e0fd6aee39325e0c6e9c23b45f36e3d8c04b"
RULE = {
    "case": "Only the first retained failed frozen candidate, width 320.",
    "rtol": 1e-3,
    "atol": 1e-5,
    "batch_size": 16,
    "control": "Reproduce all three original complete-output comparisons before tracing.",
    "trace": "Copied unfused Paddle PIR and retained candidate, ORT_DISABLE_ALL only.",
    "stop": "First batch containing a bit difference, or any perturbed final-output control.",
    "scope": "First mapped difference in diagnostic runtime; omitted outputs remain explicit.",
    "qualified": False,
    "full_corpus_automatic": False,
}


def trace_conclusion(rows, missing, controls_valid):
    first = first_differences(rows)["first_bit_difference"]
    prior_missing = [
        row for row in missing if first and row["program_index"] < first["program_index"]
    ]
    return {
        "first_mapped_difference": first if controls_valid else None,
        "unmapped_before_difference": prior_missing,
        "earliest_operation_established": bool(controls_valid and first and not prior_missing),
        "controls_valid": controls_valid,
        "qualified": False,
    }


def prepare(output):
    if digest(STAGE / "report.json") != STAGE_REPORT:
        raise ValueError("Retained failed experiment identity changed")
    report = json.loads((STAGE / "report.json").read_text())
    previous = json.loads((STAGE / "protocol.json").read_text())
    if (
        report["experiment_2_passed"]
        or len(report["cases"]) != 1
        or report["cases"][0]["role"] != "frozen"
        or report["cases"][0]["width"] != 320
        or report["protocol_sha256"] != digest(STAGE / "protocol.json")
    ):
        raise ValueError("Expected the unchanged first failed experiment")
    entry = previous["runs"][0]
    candidate = STAGE / "frozen/recognizer.onnx"
    if digest(candidate) != report["runs"][0]["artifact_sha256"]:
        raise ValueError("Retained candidate changed")
    sources = dict(previous["sources"])
    for path in [
        STAGE / "report.json",
        STAGE / "protocol.json",
        candidate,
        Path(__file__).resolve(),
    ]:
        sources[str(path)] = digest(path)
    unchanged(sources)
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    write(
        output / "protocol.json",
        {
            "rule": RULE,
            "sources": sources,
            "run": entry["run"],
            "unfused": entry["unfused"],
            "candidate": str(candidate),
            "case": entry["cases"][0],
            "previous": report["cases"][0],
            "packages": previous["packages"],
        },
    )
    print("Prepared one retained failure; no inference and no new deployment artifact.")


def execute(output):
    import numpy as np
    import onnx
    import onnxruntime as ort
    import paddle
    import yaml
    from export_parity import normalized_image
    from stage_parity import compare as compare_final

    protocol = json.loads((output / "protocol.json").read_text())
    if protocol["rule"] != RULE or any(
        importlib.metadata.version(name) != version
        for name, version in protocol["packages"].items()
    ):
        raise ValueError("Prepared protocol or runtime changed")
    sources = protocol["sources"] | {
        str(output / "protocol.json"): digest(output / "protocol.json")
    }
    unchanged(sources)
    with (output / "execution.json").open("x") as stream:
        json.dump({"pid": os.getpid(), "protocol_sha256": digest(output / "protocol.json")}, stream)
    run, unfused = Path(protocol["run"]), Path(protocol["unfused"])
    sys.path.insert(0, str(ROOT / "ml/training/ocr"))
    from run_identity import validate_inputs

    _, identity = validate_inputs(run)
    sys.path.insert(0, str(ROOT / ".local/upstream/PaddleOCR"))
    from ppocr.modeling.architectures import build_model

    def options(optimized=False):
        value = ort.SessionOptions()
        value.intra_op_num_threads, value.inter_op_num_threads = 2, 1
        value.graph_optimization_level = (
            ort.GraphOptimizationLevel.ORT_ENABLE_ALL
            if optimized
            else ort.GraphOptimizationLevel.ORT_DISABLE_ALL
        )
        value.log_severity_level = 3
        return value

    def session(path, optimized=False):
        return ort.InferenceSession(
            str(path), sess_options=options(optimized), providers=["CPUExecutionProvider"]
        )

    paddle.set_device("cpu")
    pixels = normalized_image(protocol["case"]["image"], protocol["case"]["width"])
    dynamic = build_model(yaml.safe_load((run / "export.yml").read_text())["Architecture"])
    dynamic.set_state_dict(paddle.load(str(run / "selected.pdparams")))
    dynamic.eval()
    with paddle.no_grad():
        reference = dynamic(paddle.to_tensor(pixels)).numpy()
    del dynamic
    gc.collect()
    report = {
        "qualified": False,
        "full_corpus_started": False,
        "protocol_sha256": digest(output / "protocol.json"),
        "training_identity": identity,
        "case": protocol["case"],
        "optimized_controls": {},
        "batches": [],
        "operations": [],
        "status": "running",
    }
    try:
        for name, path in [
            ("original", run / "deployment/recognizer.onnx"),
            ("unfused", unfused / "recognizer.onnx"),
            ("candidate", Path(protocol["candidate"])),
        ]:
            control = session(path, optimized=True)
            value = control.run(None, {control.get_inputs()[0].name: pixels})[0]
            comparison = compare_final(reference, value)
            report["optimized_controls"][name] = comparison
            if comparison != protocol["previous"][name]:
                raise ValueError(f"Original {name} control not reproduced")
            del control
            gc.collect()
        baseline = paddle.jit.load(str(unfused / "inference"))
        baseline.eval()
        with paddle.no_grad():
            paddle_control = baseline(paddle.to_tensor(pixels)).numpy()
        if not np.array_equal(reference, paddle_control):
            raise ValueError("Unfused static Paddle no longer equals the selected dynamic model")
        del baseline
        graph = onnx.load(protocol["candidate"])
        control = session(protocol["candidate"])
        onnx_control = control.run(None, {control.get_inputs()[0].name: pixels})[0]
        report["unoptimized_final"] = compare_final(reference, onnx_control)
        del control
        original = json.loads((unfused / "inference.json").read_text())
        _, aligned, missing = instrument_pir(
            original, {name for node in graph.graph.node for name in node.output}
        )
        report["unmapped_float_outputs"] = missing
        report["aligned_outputs"] = len(aligned)
        valid = True
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
                onnx.save(observed, folder / "observed.onnx")
                native = session(folder / "observed.onnx")
                model = paddle.jit.load(str(folder / "inference"))
                model.eval()
                with paddle.no_grad():
                    expected = [value.numpy() for value in model(paddle.to_tensor(pixels))]
                actual = native.run(None, {native.get_inputs()[0].name: pixels})
                if len(expected) != len(batch) + 1 or len(actual) != len(expected):
                    raise ValueError("Output alignment changed")
                valid = np.array_equal(paddle_control, expected[0]) and np.array_equal(
                    onnx_control, actual[0]
                )
                report["batches"].append(
                    {
                        "start": start,
                        "count": len(batch),
                        "controls_bitwise_equal": bool(valid),
                        "paddle_graph_sha256": digest(folder / "inference.json"),
                        "onnx_graph_sha256": digest(folder / "observed.onnx"),
                    }
                )
                for row, left, right in zip(batch, expected[1:], actual[1:], strict=True):
                    report["operations"].append({**row, **compare(left, right)})
                conclusion = trace_conclusion(report["operations"], missing, valid)
                if conclusion["first_mapped_difference"]:
                    first = conclusion["first_mapped_difference"]
                    index = next(
                        i + 1
                        for i, row in enumerate(batch)
                        if row["onnx_name"] == first["onnx_name"]
                    )
                    fixture = output / "first-difference.npz"
                    np.savez_compressed(
                        fixture, paddle=expected[index], onnx=actual[index], pixels=pixels
                    )
                    report["first_difference_tensors_sha256"] = digest(fixture)
                del model, native, observed, expected, actual
                gc.collect()
            print(f"Traced {len(report['operations'])}/{len(aligned)} mapped outputs", flush=True)
            if not valid or conclusion["first_mapped_difference"]:
                break
        report.update(trace_conclusion(report["operations"], missing, valid))
        report["status"] = "diagnosed-not-qualified" if valid else "instrumentation-perturbs-output"
    except Exception as error:
        report["status"] = "failed-control-or-execution"
        report["error"] = str(error)
        raise
    finally:
        report["sources_unchanged"] = False
        try:
            unchanged(sources)
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
