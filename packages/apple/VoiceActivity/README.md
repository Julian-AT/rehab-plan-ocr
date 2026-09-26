# Pinned WebRTC VAD

Source: https://github.com/dpirch/libfvad
Commit: `532ab666c20d3cfda38bca63abbb0f152706c369`
Archive SHA-256: `bf639e4a5bc37b1c90e047c42524e80a1d0cecadeb6e0a61a33580fca22a00ab`

The `src` and `include` directories are copied unchanged. No network dependency at build/run time. BSD license, patent grant and authors included; app resources include the license and patent grant. The Swift adapter converts echo-processed microphone audio to mono PCM16 at 16 kHz, feeds 320 samples (20 ms), and selects aggressiveness mode 2. The source is CPU-only and does not capture or retain audio.
