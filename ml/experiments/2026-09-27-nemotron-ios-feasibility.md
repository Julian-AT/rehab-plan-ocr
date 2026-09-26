# Native NVIDIA speech runtime: iOS compilation feasibility

NeMo-Speech.cpp's ASR C ABI and C++ runtime **cross-compile and link for arm64 iOS
26.0**, using the iOS 26.4 SDK, Accelerate and Metal. `vtool -show-build` reports
platform IOS, minimum 26.0, SDK 26.4. This is a compile experiment without weights,
inference, a phone installation or an app adapter. It does not qualify Nemotron's
streaming latency, German quality, actual Metal execution or iPhone compatibility.

The [registry card](../registry/nemotron-ios-feasibility-001.json) pins all source
revisions and hashes the retained libraries and logs. No runtime was added to the
shipping app, and no existing model evaluation was altered. Sources, dependencies,
build trees and libraries remain private under `.local/experiments/ai-upgrade`.

## Reproduction

Use NVIDIA revision `97a15afa5caa9bce5baaa86c1184103877af4101`, its ggml submodule
`c03b4e2bcece5134827881af90242086daf75be5`, and SentencePiece
`17d7580d6407802f85855d2cc9190634e2c95624` (the revision pinned by NVIDIA's dependency
script). Only the ggml submodule is needed for this experiment; no TTS LFS assets
or model files were materialized. CMake is 3.31.6 via the existing pinned `uv` project.

The initial iOS configure stopped because SentencePiece was absent. Cross-compiling
SentencePiece with only CMAKE_SYSTEM_NAME=iOS then failed on `set_xcode_property`.
Its bundled `cmake/ios.toolchain.cmake` supplies that macro. Configure it with:

```sh
cmake -S sentencepiece -B sentencepiece-ios-toolchain \
  -DCMAKE_TOOLCHAIN_FILE=cmake/ios.toolchain.cmake -DPLATFORM=OS64 \
  -DDEPLOYMENT_TARGET=26.0 -DENABLE_BITCODE=OFF -DENABLE_ARC=OFF \
  -DCMAKE_BUILD_TYPE=Release -DSPM_BUILD_TEST=OFF -DSPM_ENABLE_SHARED=OFF \
  -DSPM_ENABLE_TCMALLOC=OFF
cmake --build sentencepiece-ios-toolchain --target sentencepiece-static -j 4
```

Configure NeMo-Speech.cpp with the following settings and absolute paths to the
resulting archive and SentencePiece's `src` headers:

```sh
cmake -S nemo-speech -B nemo-ios \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DNEMO_SPEECH_BUILD_DIAR=OFF -DNEMO_SPEECH_BUILD_TTS=OFF \
  -DNEMO_SPEECH_BUILD_CLI=OFF -DNEMO_SPEECH_BUILD_MIC_CAPTURE=OFF \
  -DNEMO_SPEECH_GGML_PATCHED=OFF -DGGML_METAL=ON -DGGML_NATIVE=OFF \
  -DSENTENCEPIECE_LIB=/absolute/sentencepiece-ios-toolchain/src/libsentencepiece.a \
  -DSENTENCEPIECE_INCLUDE_DIR=/absolute/sentencepiece/src
cmake --build nemo-ios --target nemo_speech_asr_c -j 4
```

No upstream source patches were necessary. This deliberately exercises the supported
stock ggml path; optional NVIDIA patches are not part of this result. Upstream
compiler warnings remain in the retained log. Dynamic libraries link through
`@rpath` to ggml's CPU, BLAS, Metal and base libraries.

Still required: package/sign frameworks and Metal resources; implement the bounded
recognition-provider adapter and cancellation; pin/convert a permitted model;
exercise cached streaming state, real-time pacing, silence and interruption on the
phone; measure combined memory/thermal behavior; compare paired held-out Austrian
German dialogue. The gated Core ML distribution was not accessed. Apple remains
the incumbent while these questions are unresolved.
