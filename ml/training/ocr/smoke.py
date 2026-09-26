"""Prove short training/export on invented text; never a quality qualification.

The default prepares an auditable run. --execute also runs official training,
export and ONNX conversion. All artifacts stay in the chosen local run directory.
"""

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import yaml
from PIL import Image, ImageDraw, ImageFont
from preflight import ROOT, sha

TEXTS = {
    "train": [
        "Physiotherapie",
        "Raum 2.14",
        "09:30",
        "17.09.2030",
        "Ergotherapie",
        "10:15",
        "30 Minuten",
        "Frau Elandora",
    ],
    "validation": ["Bewegungsgruppe", "Raum 3.07", "14:45", "18.09.2030"],
}


def prepare(output, font_path, source, weights):
    output.mkdir(parents=True, exist_ok=False)
    font = ImageFont.truetype(str(font_path), 24)
    dictionary = (source / "ppocr/utils/dict/ppocrv6_dict.txt").read_text().splitlines()
    allowed = set(dictionary) | {" "}
    records = []
    for partition, texts in TEXTS.items():
        labels = []
        for index, text in enumerate(texts):
            if any(c not in allowed for c in text):
                raise ValueError(
                    "Synthetic target has characters missing from the deployment dictionary"
                )
            box = font.getbbox(text)
            width, height = box[2] - box[0], box[3] - box[1]
            if width + 20 > 320 or height + 12 > 48:
                raise ValueError("Synthetic text would be clipped; choose a smaller recorded font")
            image = Image.new("RGB", (width + 20, 48), "white")
            ImageDraw.Draw(image).text(
                (10 - box[0], (48 - height) // 2 - box[1]), text, font=font, fill="black"
            )
            path = output / f"{partition}-{index}.png"
            image.save(path)
            labels.append(f"{path.name}\t{text}\n")
            records.append(
                {
                    "id": path.stem,
                    "group": path.stem,
                    "partition": partition,
                    "state": "legible",
                    "text": text,
                    "image_sha256": sha(path),
                    "kind": "invented-smoke-text",
                    "size": list(image.size),
                }
            )
        (output / f"{partition}.txt").write_text("".join(labels))
    config = yaml.safe_load((source / "configs/rec/PP-OCRv6/PP-OCRv6_small_rec.yml").read_text())
    global_config = config["Global"]
    # Keep the pretrained auxiliary head shape; every target must still fit.
    maximum = max(len(record["text"]) for record in records)
    if maximum > global_config["max_text_length"]:
        raise ValueError(
            "Targets exceed this smoke architecture's label length; none were truncated"
        )
    global_config.update(
        use_gpu=False,
        distributed=False,
        epoch_num=1,
        seed=20260916,
        print_batch_step=1,
        log_smooth_window=1,
        eval_batch_step=[0, 1],
        save_epoch_step=1,
        save_model_dir=str(output / "checkpoints"),
        character_dict_path=str(source / "ppocr/utils/dict/ppocrv6_dict.txt"),
        pretrained_model=str(weights),
        checkpoints=None,
    )
    config["Optimizer"]["lr"].update(learning_rate=0.00001, warmup_epoch=0)
    for name, partition in [("Train", "train"), ("Eval", "validation")]:
        data = config[name]
        data["dataset"].update(
            data_dir=str(output), label_file_list=[str(output / f"{partition}.txt")]
        )
        data["loader"].update(batch_size_per_card=2, num_workers=0, drop_last=False)
    config["Train"]["sampler"].update(first_bs=2, scales=[[320, 48]], fix_bs=True)
    # Smoke data tests the export path, without unrecorded random augmentation.
    config["Train"]["dataset"]["transforms"] = [
        transform
        for transform in config["Train"]["dataset"]["transforms"]
        if not ({"RecConAug", "RecAug"} & transform.keys())
    ]
    (output / "config.yml").write_text(yaml.safe_dump(config, allow_unicode=True))
    (output / "samples.jsonl").write_text(
        "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in records)
    )
    return {
        "schema_version": 1,
        "kind": "synthetic-training-export-smoke",
        "qualified": False,
        "status": "prepared",
        "font_sha256": sha(font_path),
        "seed": 20260916,
        "max_verified_label_length": maximum,
        "configuration_sha256": sha(output / "config.yml"),
        "dataset_sha256": sha(output / "samples.jsonl"),
        "checkpoint_sha256": sha(weights),
        "environment_sha256": sha(Path(__file__).with_name("uv.lock")),
        "source_sha256": sha(Path(__file__)),
        "stages": [],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--font", type=Path, required=True)
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args()
    output = args.output.resolve()
    source = ROOT / ".local/upstream/PaddleOCR"
    weights = ROOT / ".local/models/ocr/PP-OCRv6_small_rec_pretrained.pdparams"
    # Verify the exact source/checkpoint before creating any run artifacts.
    subprocess.run(
        [sys.executable, str(Path(__file__).with_name("restore.py")), "--offline"], check=True
    )
    report = prepare(output, args.font, source, weights)
    report["upstream_revision"] = subprocess.check_output(
        ["git", "-C", str(source), "rev-parse", "HEAD"], text=True
    ).strip()
    report_path = output / "run.json"

    def save():
        temporary = report_path.with_suffix(".tmp")
        temporary.write_text(json.dumps(report, indent=2) + "\n")
        temporary.replace(report_path)

    save()
    if not args.execute:
        print(f"Prepared synthetic run: {output}")
        return
    commands = [
        ("training", [sys.executable, "tools/train.py", "-c", str(output / "config.yml")]),
        (
            "export",
            [
                sys.executable,
                "tools/export_model.py",
                "-c",
                str(output / "config.yml"),
                "-o",
                f"Global.pretrained_model={output}/checkpoints/latest",
                f"Global.save_inference_dir={output}/export",
            ],
        ),
        (
            "onnx",
            [
                str(Path(sys.executable).with_name("paddle2onnx")),
                "--model_dir",
                str(output / "export"),
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
    ]
    env = dict(os.environ, OMP_NUM_THREADS="2", OPENBLAS_NUM_THREADS="2", MKL_NUM_THREADS="2")
    try:
        for name, command in commands:
            stage = {"name": name, "command": command, "status": "running", "started": time.time()}
            report["stages"].append(stage)
            report["status"] = "running"
            save()
            with (output / f"{name}.log").open("w") as log:
                subprocess.run(
                    command, cwd=source, env=env, stdout=log, stderr=subprocess.STDOUT, check=True
                )
            stage.update(status="completed", elapsed_seconds=time.time() - stage["started"])
            save()
        report["artifact_sha256"] = sha(output / "recognizer.onnx")
        report["status"] = "exported-awaiting-parity"
    except BaseException:
        report["status"] = "interrupted-or-failed"
        save()
        raise
    save()
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
