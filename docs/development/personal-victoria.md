# Personal Victoria profile

The optional personal build reads the original `voice.neural.id = victoria`
preference and uses the pinned local Kokoro/Victoria model. The default project
uses installed Apple system voices.

`VictoriaSpeechRenderer` implements the existing speech renderer boundary.
Native inference remains on the Rust blocking worker, PCM decoding runs off the
main actor, and the existing playback queue owns interruption and heard-word
progress. Cancelled or superseded renders cannot start playback. The UI, controls,
calendar confirmation, app identifiers and stored data are unchanged.

## Build and package

The explicit `apps/ios/private-victoria.yml` overlay enables
`REHA_PRIVATE_VICTORIA`, bundles the pinned voice and notices, and selects a
separate ignored RehaCore package/XCFramework compiled with `kokoro`. The ordinary
project and native framework link remain unchanged. Private weights and build
products stay outside Git.

Restore and verify the separately pinned speech model and phonemizer explicitly,
then build into a new output directory:

```sh
make restore-experimental-speech
make convert-experimental-speech TARGET=all
python3 tooling/build/build-private-victoria.py simulator --output /absolute/new/build-directory
python3 tooling/build/build-private-victoria.py archive --output /absolute/new/archive-directory
python3 tooling/release/package-native.py --run .local/releases/new-run \
  --archive /absolute/new/archive-directory/Laßnitzhöhe.xcarchive --private-victoria
```

Use unsynchronized storage under `Library/Developer/RehaCalendar/Builds` for
signed outputs; the workspace File Provider can reapply signing-breaking Finder
metadata. The builder holds the native-input lease and restores the ordinary
Xcode project even on failure. It does not install on a phone.

The default package verifier rejects private builds. Explicit personal packaging
checks voice/model hashes, source identities, phonemizer build receipts and native
entry points, the separate notices, and all ordinary signature, provisioning,
App Group and dSYM checks. The base dependency inventory describes the ordinary
runtime; the bundled `private-speech/manifest.json` supplements it for Victoria.
This profile does not claim public-distribution qualification.

## Speech and qualification

German speech assets are prepared before capture, with bounded cancellable setup.
Initial preparation can need Internet. Native rendering, PCM preparation and
ordered playback retain cancellation ownership. Simulator playback and synthetic
endpoint checks do not qualify real microphone-to-answer reliability, listening
quality or device speed. This source cleanup installs no phone build.
