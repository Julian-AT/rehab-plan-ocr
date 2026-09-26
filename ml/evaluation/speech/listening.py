"""Create local, anonymous German listening samples; never select a winner automatically."""

import argparse
import array
import hashlib
import importlib.util
import json
import platform
import random
import shutil
import subprocess
import sys
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
    return hashlib.sha256(path.read_bytes()).hexdigest()


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


def checked_samples(folder, expected):
    manifest = json.loads((folder / "manifest.json").read_text())
    records = manifest["samples"]
    if len(records) != len(expected) or {r["id"] for r in records} != set(expected):
        raise ValueError("A voice omitted or duplicated a listening case")
    for record in records:
        if record["spoken_text"] != expected[record["id"]]:
            raise ValueError("Compared voices did not receive the same prepared text")
        path = folder / record["path"]
        if not path.resolve().is_relative_to(folder.resolve()):
            raise ValueError("Audio path escapes the voice export")
        identity = audio_identity(path)
        if record.get("sha256", identity["sha256"]) != identity["sha256"]:
            raise ValueError("Rendered audio changed after export")
        record.update(identity)
    return manifest


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
        HERE / "listening_form.py",
        Path(__file__),
        ROOT / "packages/rust/reha-cli/examples/voice_samples.rs",
        ROOT / "Cargo.lock",
        ROOT / "config/toolchains/versions.json",
        binary,
    ]
    identities = {str(p.relative_to(ROOT)): sha(p) for p in identity_paths}
    prepared = output / "prepared-text.json"
    run(binary, "--prepare", HERE / "prompts.json", prepared)
    records = json.loads(prepared.read_text())["samples"]
    expected = {record["id"]: record["spoken_text"] for record in records}
    if set(expected) != {sample["id"] for sample in prompts["samples"]}:
        raise ValueError("Prepared text omitted a listening prompt")
    apple = output / "apple-voices"
    run(
        "swiftc",
        "-swift-version",
        "6",
        "-strict-concurrency=complete",
        "-parse-as-library",
        HERE / "AppleVoiceSamples.swift",
        "-o",
        apple,
    )
    inventory = json.loads(run(apple, "--inventory"))
    (output / "apple-inventory.json").write_text(json.dumps(inventory, indent=2) + "\n")
    voices = []
    if include_victoria:
        run(
            binary,
            ROOT / ".local/models/runtime/kokoro-german",
            HERE / "prompts.json",
            output / "victoria",
            timeout=600,
        )
        voices.append(("victoria", checked_samples(output / "victoria", expected)))
    for index, voice in enumerate(inventory):
        folder = f"apple-{index}"
        run(apple, voice["id"], prepared, output / folder, timeout=600)
        voices.append((folder, checked_samples(output / folder, expected)))
    if not voices:
        raise ValueError("No German system voices are installed; listening export is incomplete")
    if identities != {str(p.relative_to(ROOT)): sha(p) for p in identity_paths}:
        raise ValueError("Listening source or binary changed during rendering")
    random.Random("reha-german-listening-v1").shuffle(voices)
    blind = output / "blind"
    blind.mkdir()
    mapping = {}
    for index, (folder, manifest) in enumerate(voices):
        code = f"Stimme-{index + 1:02d}"
        mapping[code] = {"folder": folder, "manifest": manifest}
        for record in manifest["samples"]:
            shutil.copy2(output / folder / record["path"], blind / f"{code}-{record['id']}.wav")
    report = {
        "schema_version": 1,
        "host": platform.platform(),
        "python": sys.version,
        "swift": run("swiftc", "--version").strip(),
        "rust": run("rustc", "--version").strip(),
        "source_revision": run("git", "-C", ROOT, "rev-parse", "HEAD").strip(),
        "binary_linkage": run("otool", "-L", binary).strip(),
        "voices": len(voices),
        "samples_per_voice": len(expected),
        "source_identities": identities,
        "rendered_samples": len(voices) * len(expected),
        "shipping_ios_route": False,
        "offline_mode_verified": False,
        "human_listening_completed": False,
        "promoted_voice": None,
        "includes_experimental_victoria": include_victoria,
        "key": mapping,
    }
    (output / "manifest.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    listening_page(output, list(mapping), prompts["samples"], sha(output / "manifest.json"))
    shutil.copy2(HERE / "prompts.json", output / "prompts.json")
    print(json.dumps({k: report[k] for k in ["voices", "rendered_samples", "promoted_voice"]}))


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
