# Personal-device Victoria restoration

The user explicitly requested restoration of the existing Victoria voice after
the 2026092701 update selected Apple speech instead. That update retained the
saved `voice.neural.id = victoria` and speech rate, but its system renderer read
another preference key. The personal build now reads the original preference
and uses the original pinned local Kokoro/Victoria model.

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

After restoring the existing pinned speech model and phonemizer, build with:

```sh
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

## Recognition repair in the same update

Observed microphone-only and duplex trials both produced voiced audio but failed
on follow-up turns using the legacy de-AT recognizer. Disabling voice processing
did not resolve the failure. Previously, absent SpeechAnalyzer assets silently
selected that legacy recognizer. Initial preparation now installs and reserves
supported German assets before capture; subsequent turns require ready assets.
Only unsupported hardware/locales or the explicit legacy trial select the old
provider. Setup is cancellable and bounded, with content-free readiness/error
diagnostics. Initial asset setup can require Internet; inference stays local.

Portable checks cover setup/cancellation, incomplete recognition rejection, PCM
validation, and public/private package separation. Actual speech reliability and
the restored voice must be checked on the phone; simulator playback alone does
not qualify microphone-to-answer conversation.
