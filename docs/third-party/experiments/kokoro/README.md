# Experimental Victoria/Kokoro provenance

These unchanged notices belong to the optional host speech experiment. They are
outside the app's `licenses` resource directory and are not public-release inputs.
The shared Apache text remains at [apache-2.0.txt](../../licenses/apache-2.0.txt),
because the shipped Rust dependencies also use those exact bytes. The historical
source notice retains its old path descriptions so the pinned speech bundle and
saved evaluation identities remain reproducible; current commands are below.

```sh
make restore-experimental-speech
make convert-experimental-speech TARGET=all
make prepare-listening-experimental RUN=.local/runs/<new-run>
```

`tooling/build/fetch-speech-model.py` copies this unchanged `kokoro-source.txt` and
the shared Apache text into the experimental model folder. Existing model locks,
weights, dictionary, export recipe and results remain intact. The Rust renderer is
available through `reha-core/kokoro`, `reha-cli/voice` or the explicit
`reha-ffi/kokoro` development feature. The normal native build selects only
`reha-ffi/onnx`, which does not enable Kokoro.

The eSpeak license and redistribution obligations still apply to experiments that
include it. Excluding this implementation from the public app path does not grant
distribution rights to an experimental binary or qualify any replacement voice.
