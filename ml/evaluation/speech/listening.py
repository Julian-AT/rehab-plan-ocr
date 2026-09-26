"""Create local, anonymous German listening samples; never select a winner automatically."""

import argparse
import array
import hashlib
import importlib.util
import json
import math
import platform
import random
import shutil
import subprocess
import sys
import tempfile
import time
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tooling/dev"))
import workspace  # noqa: E402

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("listening_form", HERE / "listening_form.py")
_form = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_form)
listening_page = _form.listening_page


def sha(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def run(*args, timeout=120):
    result = subprocess.run(
        [str(arg) for arg in args], check=True, capture_output=True, text=True, timeout=timeout
    )
    return result.stdout


def audio_identity(path):
    with wave.open(str(path)) as source:
        frames, rate = source.getnframes(), source.getframerate()
        if (
            source.getsampwidth() != 2
            or source.getnchannels() not in (1, 2)
            or not 0 < frames <= rate * 300
        ):
            raise ValueError("Listening sample must be bounded, nonempty PCM16")
        samples = array.array("h", source.readframes(frames))
        if sys.byteorder != "little":
            samples.byteswap()
        if len(samples) != frames * source.getnchannels() or max(map(abs, samples), default=0) < 2:
            raise ValueError("Listening sample is empty, silent or truncated")
        return {
            "sha256": sha(path),
            "frames": frames,
            "sample_rate": rate,
            "channels": source.getnchannels(),
            "duration_seconds": frames / rate,
        }


def lexical(value):
    return "".join(character for character in value if character.isalnum())


def checked_samples(folder, expected, system=False):
    manifest = json.loads((folder / "manifest.json").read_text())
    if system and (
        manifest.get("schema_version") != 2
        or manifest.get("route") != "host-product-system-speech-renderer"
        or manifest.get("renderer") != "SystemSpeechRenderer"
        or manifest.get("shared_product_renderer") is not True
        or manifest.get("rate_multiplier") != 0.95
        or manifest.get("status") != "complete"
        or manifest.get("failed_samples") != 0
        or manifest.get("expected_samples") != len(expected)
    ):
        raise ValueError("System voice did not finish the shared product renderer contract")
    records = manifest["samples"]
    if len(records) != len(expected) or {r["id"] for r in records} != set(expected):
        raise ValueError("A voice omitted or duplicated a listening case")
    for record in records:
        if record.get("status", "complete") != "complete":
            raise ValueError("A listening case failed; retain its error manifest")
        if record["spoken_text"] != expected[record["id"]]:
            raise ValueError("Compared voices did not receive the same prepared text")
        path = folder / record["path"]
        if not path.resolve().is_relative_to(folder.resolve()):
            raise ValueError("Audio path escapes the voice export")
        identity = audio_identity(path)
        if record.get("sha256", identity["sha256"]) != identity["sha256"]:
            raise ValueError("Rendered audio changed after export")
        if system:
            if identity["channels"] != 1 or identity["sample_rate"] != 24_000:
                raise ValueError("Product-renderer audio must be mono 24 kHz PCM16")
            for key in ["frames", "sample_rate", "channels"]:
                if record.get(key) != identity[key]:
                    raise ValueError("Audio metadata does not match the rendered file")
            duration = record.get("duration_seconds", math.nan)
            if (
                not math.isfinite(duration)
                or abs(duration - identity["duration_seconds"]) > 1 / 24_000
            ):
                raise ValueError("Audio duration does not match the rendered file")
            marks = record.get("marks", [])
            if not marks:
                raise ValueError("The product renderer omitted word progress")
            previous = 0.0
            for mark in marks:
                start, end = mark["start"], mark["end"]
                if (
                    not mark.get("text")
                    or not all(math.isfinite(value) for value in [start, end])
                    or not previous <= start <= end <= duration
                ):
                    raise ValueError("Word progress is nonfinite, unordered or outside the audio")
                previous = end
            if lexical("".join(mark["text"] for mark in marks)) != lexical(record["spoken_text"]):
                raise ValueError("Word progress does not cover the prepared text exactly once")
        record.update(identity)
    return manifest


def render_voice(arguments, folder, expected, system=False):
    started = time.monotonic()
    process = {"command": [str(arg) for arg in arguments], "returncode": None, "timeout": False}
    try:
        result = subprocess.run(process["command"], capture_output=True, text=True, timeout=600)
        process.update(returncode=result.returncode, stdout=result.stdout, stderr=result.stderr)
    except subprocess.TimeoutExpired as error:
        process.update(timeout=True, stdout=error.stdout or "", stderr=error.stderr or "")
    except OSError as error:
        process.update(stdout="", stderr=str(error))
    process["elapsed_seconds"] = time.monotonic() - started
    for key in ["stdout", "stderr"]:
        value = process.pop(key)
        if isinstance(value, bytes):
            value = value.decode("utf-8", errors="replace")
        folder.with_suffix(f".{key}.log").write_text(value)
    folder.with_suffix(".process.json").write_text(json.dumps(process, indent=2) + "\n")
    try:
        if process["returncode"] != 0:
            raise ValueError(
                "Voice renderer failed or timed out; see retained process log/manifest"
            )
        return checked_samples(folder, expected, system=system), None
    except (ValueError, OSError, KeyError, TypeError, wave.Error) as error:
        failure = {"folder": folder.name, "error": str(error), "process": process}
        if (folder / "manifest.json").is_file():
            failure["manifest_sha256"] = sha(folder / "manifest.json")
        folder.with_suffix(".failure.json").write_text(json.dumps(failure, indent=2) + "\n")
        return None, failure


def prepare(output, binary, include_victoria=False):
    output = output.resolve()
    if not output.is_relative_to(ROOT / ".local/runs") or output.exists():
        raise ValueError("Use a new listening run under .local/runs")
    prompts = json.loads((HERE / "prompts.json").read_text())
    if prompts.get("synthetic") is not True or prompts.get("human_reviewed") is not False:
        raise ValueError("This development runner expects the explicitly unreviewed synthetic set")
    output.mkdir(parents=True)
    identity_paths = [
        HERE / "prompts.json",
        HERE / "AppleVoiceSamples.swift",
        HERE / "SpeechSampleFile.swift",
        ROOT / "apps/ios/Features/Conversation/SystemSpeech.swift",
        ROOT / "apps/ios/Features/Conversation/OutputAudio.swift",
        HERE / "listening_form.py",
        Path(__file__),
        ROOT / "packages/rust/reha-cli/examples/voice_samples.rs",
        ROOT / "Cargo.lock",
        ROOT / "config/toolchains/versions.json",
        binary,
    ]
    identities = {str(p.relative_to(ROOT)): sha(p) for p in identity_paths}
    revision = run("git", "-C", ROOT, "rev-parse", "HEAD").strip()
    (output / "source-identities.json").write_text(
        json.dumps({"revision": revision, "files": identities}, indent=2) + "\n"
    )
    prepared = output / "prepared-text.json"
    run(binary, "--prepare", HERE / "prompts.json", prepared)
    records = json.loads(prepared.read_text())["samples"]
    expected = {record["id"]: record["spoken_text"] for record in records}
    if len(records) != len(expected) or set(expected) != {
        sample["id"] for sample in prompts["samples"]
    }:
        raise ValueError("Prepared text omitted a listening prompt")
    apple = output / "apple-voices"
    build_root = ROOT / ".local/builds/probes"
    build_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="listening-modules-", dir=build_root) as modules:
        command = [
            "swiftc",
            "-swift-version",
            "6",
            "-strict-concurrency=complete",
            "-parse-as-library",
            "-O",
            "-target",
            f"{platform.machine()}-apple-macos26.0",
            "-module-cache-path",
            modules,
            HERE / "AppleVoiceSamples.swift",
            HERE / "SpeechSampleFile.swift",
            ROOT / "apps/ios/Features/Conversation/SystemSpeech.swift",
            ROOT / "apps/ios/Features/Conversation/OutputAudio.swift",
            "-o",
            apple,
        ]
        (output / "compiler-command.json").write_text(
            json.dumps(list(map(str, command)), indent=2) + "\n"
        )
        result = subprocess.run(
            list(map(str, command)), capture_output=True, text=True, timeout=120
        )
        (output / "compiler.stdout.log").write_text(result.stdout)
        (output / "compiler.stderr.log").write_text(result.stderr)
        result.check_returncode()
    inventory = json.loads(run(apple, "--inventory"))
    (output / "apple-inventory.json").write_text(json.dumps(inventory, indent=2) + "\n")
    if len({voice["id"] for voice in inventory}) != len(inventory) or any(
        not voice["language"].startswith("de-") for voice in inventory
    ):
        raise ValueError("System inventory contains duplicate or non-German voices")
    generated_paths = [prepared, apple, output / "apple-inventory.json"]
    generated = {p.name: sha(p) for p in generated_paths}
    voices = []
    failures = []
    if include_victoria:
        manifest, failure = render_voice(
            [
                binary,
                ROOT / ".local/models/runtime/kokoro-german",
                HERE / "prompts.json",
                output / "victoria",
            ],
            output / "victoria",
            expected,
        )
        if failure:
            failures.append(failure | {"voice": "victoria", "experimental": True})
        else:
            voices.append(("victoria", manifest))
    for index, voice in enumerate(inventory):
        folder = f"apple-{index}"
        manifest, failure = render_voice(
            [apple, voice["id"], prepared, output / folder], output / folder, expected, system=True
        )
        if failure:
            failures.append(failure | {"voice": voice["id"], "experimental": False})
        else:
            if manifest["prepared_text_sha256"] != generated[prepared.name]:
                raise ValueError("System renderer did not consume the retained prepared text")
            voices.append((folder, manifest))
    final_identities = {str(p.relative_to(ROOT)): sha(p) for p in identity_paths}
    final_generated = {p.name: sha(p) for p in generated_paths}
    stable = identities == final_identities and generated == final_generated
    (output / "source-stability.json").write_text(
        json.dumps(
            {
                "unchanged": stable,
                "sources_before": identities,
                "sources_after": final_identities,
                "generated_before": generated,
                "generated_after": final_generated,
            },
            indent=2,
        )
        + "\n"
    )
    if not stable:
        raise ValueError("Listening source or binary changed during rendering")
    random.Random("reha-german-listening-v1").shuffle(voices)
    blind = output / "blind"
    blind.mkdir()
    mapping = {}
    for index, (folder, manifest) in enumerate(voices):
        code = f"Stimme-{index + 1:02d}"
        mapping[code] = {"folder": folder, "manifest": manifest}
        for record in manifest["samples"]:
            destination = blind / f"{code}-{record['id']}.wav"
            shutil.copy2(output / folder / record["path"], destination)
            if sha(destination) != record["sha256"]:
                raise ValueError("Anonymous audio copy differs from the validated renderer output")
    report = {
        "schema_version": 2,
        "status": "complete" if voices and not failures else "failed",
        "host": platform.platform(),
        "python": sys.version,
        "swift": run("swiftc", "--version").strip(),
        "rust": run("rustc", "--version").strip(),
        "source_revision": revision,
        "binary_linkage": run("otool", "-L", binary).strip(),
        "voices": len(voices),
        "samples_per_voice": len(expected),
        "source_identities": identities,
        "generated_identities": generated,
        "sources_unchanged": stable,
        "enumerated_system_voices": len(inventory),
        "failed_voices": failures,
        "shared_product_system_renderer": True,
        "system_rate_multiplier": 0.95,
        "rendered_samples": len(voices) * len(expected),
        "shipping_ios_route": False,
        "offline_mode_verified": False,
        "human_listening_completed": False,
        "promoted_voice": None,
        "includes_experimental_victoria": include_victoria,
        "key": mapping,
    }
    (output / "manifest.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    if voices:
        listening_page(output, list(mapping), prompts["samples"], sha(output / "manifest.json"))
    shutil.copy2(HERE / "prompts.json", output / "prompts.json")
    print(json.dumps({k: report[k] for k in ["voices", "rendered_samples", "promoted_voice"]}))
    if report["status"] != "complete":
        raise ValueError(
            "Not all enumerated voices completed; inspect retained failures before comparison"
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument(
        "--binary",
        type=Path,
        default=workspace.cargo_directory(ROOT) / "debug/examples/voice_samples",
    )
    parser.add_argument("--include-victoria", action="store_true")
    args = parser.parse_args()
    prepare(args.run, args.binary.resolve(), args.include_victoria)
