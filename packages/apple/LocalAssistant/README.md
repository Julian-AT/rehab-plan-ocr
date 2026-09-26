# Experimental local assistant runtime

This package runs the existing Qwen3-0.6B GGUF export through a small C boundary and
Swift 6 background executor. It is not selected or bundled by the production app.
The trained candidate still fails the quality and desktop export-parity gates.
An executable runtime does not qualify its answers or authorize calendar changes.

The native source is the same unmodified llama.cpp revision pinned by
[`assistant-base.json`](../../../ml/registry/assistant-base.json). Build tooling
uses CMake and Xcode from restored local sources, without importing training
packages. Native source, toolchain, architecture, flags and complete output hashes
identify each cache entry. The package's ignored XCFramework link exposes only a
completed verified product. Each library retains the upstream MIT license.

```sh
make build-assistant-native                             # host and arm64 simulator
make build-assistant-native ASSISTANT_NATIVE_TARGETS='host simulator device'
make test-assistant-native TEST_ARGS='--run .local/runs/<new-run>'
make test-assistant-native TEST_ARGS='--run .local/runs/<new-run> --simulator <id>'
```

The optional simulator must be a booted disposable `Termine-Native-Test-*` device;
run simulator jobs serially. The runner verifies the existing model, prompts and
development reference identities. It compiles the real package into an isolated
iOS probe app, verifies the copied model and requires a fresh completed report.
An exit code from `simctl launch` is insufficient. All output remains in `.local`.
No physical device is installed or updated by this tool.

`LocalAssistant` verifies model size/SHA-256 off the main thread. Models are reused
on one serial queue, while every generation receives fresh context and sampler
state. The C boundary uses greedy sampling, four CPU threads, a 2,048-token context,
at most 192 output tokens and at most 8,192 output bytes. It returns only completed
output; truncation, cancellation and deadlines discard partial results. Swift
validates UTF-8 and checks cancellation/deadline again before delivery. Independent
operation ownership keeps native cancellation pointers alive until work finishes.

CPU is the first compatibility route. Metal, quantization, session/context reuse,
memory/energy/thermal effects and real-device latency require separate comparisons.
The runtime probe covers actual inference, cancellation, deadlines, context/output
limits and repeatability after abandoned requests. Model answers are scored against
the original invented development cases and compared with the prior desktop GGUF
outputs. These correlated checks do not increase the independent data count.

The app still needs the strict structured-output adapter, common-provider trials,
approved help content and a qualified model before production selection. Live
calendar lookup, ownership/snapshot validation and visible mutation confirmation
remain app responsibilities. Package linkage/notices must join the shipping
inventory when that integration becomes part of the app's selected build.

Implementation references: the pinned source's `include/llama.h`, `examples/simple`
and [official Apple build script](https://github.com/ggml-org/llama.cpp/blob/41fc7584f0c1d72d9cc1ac46ccae8defc1587f0f/build-xcframework.sh).
