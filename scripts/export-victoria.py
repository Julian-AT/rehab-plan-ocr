# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = ["torch==2.8.0", "kokoro==0.9.4", "onnx==1.18.0", "onnxruntime==1.22.0"]
# ///
"""Convert pinned Victoria weights locally; no model code or pickle code is loaded.

Run with uv run --locked scripts/export-victoria.py. fetch-speech-model.py calls this only
when the checked ONNX model is missing. All products remain under models/private.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import numpy as np
import onnx
import onnxruntime as ort
import torch
from kokoro import KModel
from kokoro.model import KModelForONNX

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "models/private/kikiri-victoria-source"
TARGET = ROOT / "models/private/kokoro-german"
REVISION = "ce81e200ff9203e1a3b042cd678c48e3ffb85cef"
ASSETS = {
    "model.pth": (f"kikiri-tts/kikiri-german-victoria/resolve/{REVISION}/kikiri_german_victoria_ep10.pth", "128d1c4a4184a459f23cb307a6cbbb8e9c076c2526f86e18594c1b320a81e00c"),
    "victoria.pt": (f"kikiri-tts/kikiri-german-victoria/resolve/{REVISION}/voices/victoria.pt", "18dbcf0afa7b737e450e6ba769ee898a5aae1d90218265ff4c95422f4693da50"),
    "config.json": ("hexgrad/Kokoro-82M/resolve/f3ff3571791e39611d31c381e3a41a3af07b4987/config.json", "5abb01e2403b072bf03d04fde160443e209d7a0dad49a423be15196b9b43c17f"),
}
SOURCE.mkdir(parents=True, exist_ok=True)
TARGET.mkdir(parents=True, exist_ok=True)
for name, (remote, digest) in ASSETS.items():
    destination = SOURCE / name
    if not destination.exists() or hashlib.sha256(destination.read_bytes()).hexdigest() != digest:
        temporary = destination.with_suffix(".download")
        subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error", "--retry", "3", "--max-time", "600", "https://huggingface.co/" + remote, "-o", str(temporary)], check=True)
        assert hashlib.sha256(temporary.read_bytes()).hexdigest() == digest, name
        temporary.replace(destination)

config = json.loads((SOURCE / "config.json").read_text())
assert config["vocab"] == json.loads((ROOT / "models/kokoro-vocab.json").read_text())
torch.set_num_threads(4)
torch.manual_seed(0)
model = KModel(repo_id="hexgrad/Kokoro-82M", config=config, model=str(SOURCE / "model.pth"), disable_complex=True).eval()
# KModel has a permissive compatibility fallback. Verify every learned tensor,
# so a shape/key mismatch can never silently ship random parameters.
weights = torch.load(SOURCE / "model.pth", map_location="cpu", weights_only=True)
for module, source_state in weights.items():
    state = {key.removeprefix("module.").replace("parametrizations.weight.original0", "weight_g").replace("parametrizations.weight.original1", "weight_v"): value for key, value in source_state.items()}
    component = getattr(model, module)
    # StyleTTS2 trains these adaptive normalization layers without an extra
    # affine transform. Kokoro 0.9.4 creates one; make it an explicit identity
    # when absent in the source checkpoint.
    for name, layer in component.named_modules():
        if isinstance(layer, torch.nn.InstanceNorm1d) and layer.affine and name + ".weight" not in state:
            assert name + ".bias" not in state
            # Explicit identity constants preserve non-affine normalization and
            # expose channel size to the ONNX exporter for dynamic sequences.
            state[name + ".weight"] = torch.ones_like(layer.weight)
            state[name + ".bias"] = torch.zeros_like(layer.bias)
            layer.requires_grad_(False)
    missing = set(component.state_dict()) - set(state)
    assert all(module == "decoder" and key.startswith("generator.stft.") for key in missing), (module, missing)
    # The real-valued STFT export adds deterministic, non-learned filter buffers.
    state.update({key: component.state_dict()[key] for key in missing})
    component.load_state_dict(state, strict=True)
    for name, parameter in component.named_parameters():
        assert name in state and torch.equal(parameter, state[name]), (module, name)
voice = torch.load(SOURCE / "victoria.pt", map_location="cpu", weights_only=True)
assert voice.shape == (510, 1, 256) and torch.isfinite(voice).all(), voice.shape
voice.numpy().astype("<f4").tofile(TARGET / "voice.f32")
wrapper = KModelForONNX(model).eval()
ids = torch.tensor([[0, 50, 43, 54, 55, 16, 44, 47, 62, 4, 0]], dtype=torch.int64)
style = voice[ids.shape[1] - 3]
speed = torch.tensor([0.95], dtype=torch.float32)
output = TARGET / "model.onnx"
with torch.no_grad():
    torch.onnx.export(wrapper, (ids, style, speed), str(output), dynamo=False,
        input_names=["input_ids", "style", "speed"], output_names=["waveform", "duration"],
        dynamic_axes={"input_ids": {1: "tokens"}, "waveform": {0: "samples"}, "duration": {0: "tokens"}},
        opset_version=17)
onnx.checker.check_model(str(output))
options = ort.SessionOptions(); options.intra_op_num_threads = 4
session = ort.InferenceSession(str(output), sess_options=options, providers=["CPUExecutionProvider"])
checks = []
for n, tempo in [(11, 0.95), (6, 0.75), (11, 1.25)]:
    tokens = ids[:, :n].clone(); tokens[0, -1] = 0
    ref = voice[n - 3]
    with torch.no_grad(): expected_audio, expected_duration = wrapper(tokens, ref, torch.tensor([tempo]))
    audio, duration = session.run(None, {"input_ids": tokens.numpy(), "style": ref.numpy(), "speed": np.array([tempo], dtype=np.float32)})
    assert audio.size > 2400 and np.isfinite(audio).all() and np.max(np.abs(audio)) > 0.01
    assert np.array_equal(duration, expected_duration.numpy()), "Export changed duration prediction"
    assert audio.shape == expected_audio.numpy().shape, "Export changed waveform length"
    checks.append({"tokens": n, "speed": tempo, "samples": audio.size, "peak": float(np.max(np.abs(audio)))})
report = {"source_revision": REVISION, "checks": checks, "onnx_sha256": hashlib.sha256(output.read_bytes()).hexdigest(), "voice_sha256": hashlib.sha256((TARGET / "voice.f32").read_bytes()).hexdigest()}
(SOURCE / "export-verification.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
