#!/bin/sh
# Reproducible native build. Signing and installation are explicit modes only.
set -eu
cd "$(dirname "$0")/../.."
export PATH="$HOME/.cargo/bin:$PATH"
export CARGO_PROFILE_DEV_DEBUG=0 CARGO_INCREMENTAL=0
mode=${1:-simulator}
bindings() {
  cargo build --locked -p reha-ffi --features bindgen
  generated=$(mktemp -d)
  target/debug/reha-bindgen generate target/debug/libreha_ffi.dylib --language swift --metadata-no-deps --no-format --out-dir "$generated"
  if [ "$mode" != bindings ]; then
    diff -u packages/apple/RehaCore/Sources/RehaCore/RehaCore.swift "$generated/RehaCore.swift"
    diff -u packages/apple/RehaCore/Headers/RehaCoreFFI.h "$generated/RehaCoreFFI.h"
    diff -u packages/apple/RehaCore/Headers/module.modulemap "$generated/RehaCoreFFI.modulemap"
  else
    cp "$generated/RehaCore.swift" packages/apple/RehaCore/Sources/RehaCore/
    cp "$generated/RehaCoreFFI.h" packages/apple/RehaCore/Headers/
    cp "$generated/RehaCoreFFI.modulemap" packages/apple/RehaCore/Headers/module.modulemap
  fi
  rm -rf "$generated"
}
framework() {
  python3 tooling/dev/quality.py space 2
  bindings
  uv run tooling/build/fetch-models.py --tier small
  uv run tooling/build/fetch-ios-runtime.py
  python3 tooling/build/build-phonemizer.py
  python3 tooling/build/fetch-speech-model.py
  mkdir -p apps/ios/build/ffi/device apps/ios/build/ffi/simulator
  case "$mode" in
    simulator | test) variants=simulator ;;
    device) variants=device ;;
    *) variants='device simulator' ;;
  esac
  for variant in $variants; do
    case "$variant" in
      device) triple=aarch64-apple-ios ;;
      simulator) triple=aarch64-apple-ios-sim ;;
    esac
    python3 tooling/dev/quality.py space 1.5
    IPHONEOS_DEPLOYMENT_TARGET=26.0 cargo build --locked --release -p reha-ffi --lib --features onnx --target "$triple"
    xcrun libtool -static -o "apps/ios/build/ffi/$variant/libRehaCoreFFI.a" \
      "target/$triple/release/libreha_ffi.a" "models/private/runtime/$triple/libonnxruntime.a"
    xcrun nm -g "apps/ios/build/ffi/$variant/libRehaCoreFFI.a" 2> /dev/null | rg -q ' T _OrtGetApiBase$'
    if [ "${REHA_LOW_DISK:-0}" = 1 ]; then rm -r "target/$triple/release"; fi
  done
  assembled=$(mktemp -d)
  set -- -create-xcframework
  for variant in $variants; do
    set -- "$@" -library "apps/ios/build/ffi/$variant/libRehaCoreFFI.a" -headers packages/apple/RehaCore/Headers
  done
  xcodebuild "$@" -output "$assembled/RehaCoreFFI.xcframework"
  if [ -d packages/apple/RehaCore/RehaCoreFFI.xcframework ]; then rm -r packages/apple/RehaCore/RehaCoreFFI.xcframework; fi
  mv "$assembled/RehaCoreFFI.xcframework" packages/apple/RehaCore/
  rmdir "$assembled"
}
case "$mode" in
  bindings | check-bindings) bindings ;;
  integration) sh tooling/checks/test-native-bindings.sh ;;
  framework) framework ;;
  simulator | device | archive | test)
    framework
    xcodegen generate --spec apps/ios/project.yml --project apps/ios
    case "$mode" in
      simulator) xcodebuild -project apps/ios/Termine.xcodeproj -scheme Termine -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath apps/ios/build/DerivedData CODE_SIGNING_ALLOWED=NO build ;;
      device) xcodebuild -project apps/ios/Termine.xcodeproj -scheme Termine -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath apps/ios/build/DerivedData CODE_SIGNING_ALLOWED=NO build ;;
      archive)
        xcodebuild -project apps/ios/Termine.xcodeproj -scheme Termine -configuration Release -destination 'generic/platform=iOS' -archivePath apps/ios/build/Laßnitzhöhe.xcarchive -allowProvisioningUpdates archive
        python3 tooling/release/package-native.py
        ;;
      test)
        xcodebuild -project apps/ios/Termine.xcodeproj -scheme Termine -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath apps/ios/build/DerivedData CODE_SIGNING_ALLOWED=NO build
        sh tooling/checks/test-native-ui.sh --built
        ;;
    esac
    ;;
  *)
    echo 'Usage: tooling/build/build-native.sh bindings|check-bindings|integration|framework|simulator|device|archive|test' >&2
    exit 2
    ;;
esac
