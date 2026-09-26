"""Transcribe retained synthetic listening files through installed local host ASR.

No microphone, calendar, permission prompt, implicit asset download or model/voice
promotion. Text pairs are review material, not human comprehension measurements.
"""

import argparse
import json
import math
import platform
import re
import subprocess
import uuid
from pathlib import Path

from listening import audio_identity, sha

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def write(path, value):
    with path.open("w") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2, allow_nan=False)
        stream.write("\n")


def samples(folder):
    manifest = json.loads((folder / "manifest.json").read_text())
    if (
        manifest["source_identities"]["ml/evaluation/speech/prompts.json"]
        != sha(HERE / "prompts.json")
        or manifest["human_listening_completed"] is not False
        or manifest["shipping_ios_route"] is not False
        or manifest["voices"] != len(manifest["key"])
    ):
        raise ValueError("Use the retained synthetic host listening corpus and matching prompts")
    prompts = json.loads((HERE / "prompts.json").read_text())
    expected = {row["id"] for row in prompts["samples"]}
    if prompts["synthetic"] is not True or prompts["human_reviewed"] is not False:
        raise ValueError("This development probe accepts only the declared invented corpus")
    rows, texts = [], {}
    for voice, entry in sorted(manifest["key"].items()):
        voice_folder = (folder / entry["folder"]).resolve(strict=True)
        if not voice_folder.is_relative_to(folder.resolve()):
            raise ValueError("Voice folder escapes the listening export")
        records = entry["manifest"]["samples"]
        if len(records) != len(expected) or {r["id"] for r in records} != expected:
            raise ValueError("Missing or duplicate speech cases")
        for row in records:
            path = (voice_folder / row["path"]).resolve(strict=True)
            if not path.is_relative_to(voice_folder):
                raise ValueError("Audio path escapes the voice export")
            identity = audio_identity(path)
            if any(row[key] != identity[key] for key in identity):
                raise ValueError("Listening audio identity changed")
            if texts.setdefault(row["id"], row["spoken_text"]) != row["spoken_text"]:
                raise ValueError("Voices did not receive the same prepared words")
            rows.append(dict(row, voice=voice, audio_path=str(path)))
    if len(rows) != manifest["rendered_samples"]:
        raise ValueError("Listening sample count changed")
    return rows


def validate(result, request, duration):
    if (
        result.get("stage") != "completed"
        or result.get("runID") != request["runID"]
        or result.get("requestedLocale") != request["locale"]
        or result.get("resolvedLocale", "").replace("_", "-") != request["locale"]
        or result.get("audioSHA256") != request["audioSHA256"]
        or result.get("provider") != "Apple SpeechTranscriber"
        or any(
            result.get(key) is not False
            for key in ["downloadRequested", "microphoneUsed", "physicalDevice"]
        )
        or type(result.get("seconds")) not in {int, float}
        or not math.isfinite(result["seconds"])
        or result["seconds"] < 0
        or not isinstance(result.get("segments"), list)
    ):
        raise ValueError("ASR did not finish with the requested identities and offline route")
    end = 0
    for segment in result["segments"]:
        if (
            not isinstance(segment.get("text"), str)
            or any(
                type(segment.get(k)) not in {int, float} or not math.isfinite(segment[k])
                for k in ["start", "duration"]
            )
            or segment["start"] < end - 0.001
            or segment["duration"] < 0
            or segment["start"] + segment["duration"] > duration + 0.1
        ):
            raise ValueError("ASR final segments have invalid or overlapping audio ranges")
        end = segment["start"] + segment["duration"]
    return " ".join(s["text"].strip() for s in result["segments"]).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--listening", type=Path)
    parser.add_argument(
        "--setup", action="store_true", help="Explicitly install host ASR assets; no transcription"
    )
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--locale", choices=["de-AT", "de-DE"], default="de-AT")
    args = parser.parse_args()
    if bool(args.listening) == args.setup:
        parser.error("Choose either --listening or the separate --setup action")
    output = args.run.resolve()
    if not output.is_relative_to(ROOT / ".local/runs"):
        parser.error("Use a new private run below .local/runs")
    rows = samples(args.listening.resolve()) if args.listening else []
    output.mkdir(parents=True, exist_ok=False)
    source_paths = [
        Path(__file__),
        HERE / "SpeechFileProbe.swift",
        HERE / "listening.py",
        HERE / "prompts.json",
    ]
    identities = {str(p.relative_to(ROOT)): sha(p) for p in source_paths}
    report = {
        "stage": "building",
        "qualified": False,
        "physical_device": False,
        "human_listeners": 0,
        "human_speakers": 0,
        "synthetic_audio_files": len(rows),
        "prompt_families": len({r["id"] for r in rows}),
        "host": platform.platform(),
        "source_revision": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
        ).strip(),
        "sources": identities,
        "listening_manifest_sha256": sha(args.listening / "manifest.json")
        if args.listening
        else None,
        "kind": "host-asset-setup" if args.setup else "host-synthetic-file-transcription",
        "locale": args.locale,
        "records": [],
    }
    write(output / "report.json", report)
    try:
        binary = output / "SpeechFileProbe"
        with (output / "build.log").open("w") as log:
            subprocess.run(
                [
                    "xcrun",
                    "swiftc",
                    "-parse-as-library",
                    "-swift-version",
                    "6",
                    str(HERE / "SpeechFileProbe.swift"),
                    "-o",
                    str(binary),
                ],
                check=True,
                stdout=log,
                stderr=subprocess.STDOUT,
            )
        report["binary_sha256"] = sha(binary)
        report["swift"] = subprocess.check_output(
            ["xcrun", "swiftc", "--version"], text=True
        ).strip()
        inventory = json.loads(
            subprocess.check_output([str(binary), "--inventory"], text=True, timeout=30)
        )
        report["inventory"] = inventory
        if args.setup:
            setup = json.loads(
                subprocess.check_output(
                    [str(binary), "--setup", args.locale], text=True, timeout=900
                )
            )
            report["setup"] = setup
            if setup.get("installed") is not True:
                raise ValueError("Asset installation did not finish")
            report["stage"] = "assets_installed"
            return
        selected = [v for v in inventory["locales"] if v["requested_locale"] == args.locale]
        if len(selected) != 1 or selected[0]["asset_status"] != "installed":
            raise ValueError("German ASR assets are absent; complete the explicit setup first")
        report["stage"] = "transcribing"
        for index, row in enumerate(rows):
            folder = output / f"case-{index:03}"
            folder.mkdir()
            request = {
                "runID": str(uuid.uuid4()).upper(),
                "locale": args.locale,
                "audioPath": row["audio_path"],
                "audioSHA256": row["sha256"],
            }
            write(folder / "input.json", request)
            record = {
                "voice": row["voice"],
                "sample": row["id"],
                "reference": row["spoken_text"],
                "audio_sha256": row["sha256"],
                "run_id": request["runID"],
                "case": folder.name,
            }
            try:
                with (folder / "process.log").open("w") as log:
                    subprocess.run(
                        [
                            str(binary),
                            "--transcribe",
                            str(folder / "input.json"),
                            str(folder / "result.json"),
                        ],
                        stdout=log,
                        stderr=subprocess.STDOUT,
                        check=True,
                        timeout=120,
                    )
                result = json.loads((folder / "result.json").read_text())
                text = validate(result, request, row["duration_seconds"])
                record.update(
                    status="completed",
                    text=text,
                    seconds=result["seconds"],
                    result_sha256=sha(folder / "result.json"),
                    orthographic_match=re.sub(r"\W+", "", text.casefold())
                    == re.sub(r"\W+", "", row["spoken_text"].casefold()),
                )
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                record.update(status="failed", error=str(error))
            report["records"].append(record)
            write(output / "report.json", report)
            print(
                f"{index + 1}/{len(rows)} {row['voice']} {row['id']}: {record['status']}",
                flush=True,
            )
        if identities != {
            str(p.relative_to(ROOT)): sha(p) for p in source_paths
        } or rows != samples(args.listening.resolve()):
            raise ValueError("Evaluation sources or audio changed during transcription")
        report["stage"] = (
            "completed" if all(r["status"] == "completed" for r in report["records"]) else "failed"
        )
    except Exception as error:
        report.update(stage="failed", error=str(error))
        raise
    finally:
        write(output / "report.json", report)
    if report["stage"] != "completed":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
