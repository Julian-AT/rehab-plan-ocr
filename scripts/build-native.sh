#!/bin/sh
# Reproducible native build. Signing and installation are explicit modes only.
set -eu
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"
export CARGO_PROFILE_DEV_DEBUG=0 CARGO_INCREMENTAL=0
mode=${1:-simulator}
bindings() {
  cargo build --locked -p reha-ffi --features bindgen
  generated=$(mktemp -d)
  target/debug/reha-bindgen generate target/debug/libreha_ffi.dylib --language swift --metadata-no-deps --no-format --out-dir "$generated"
  if [ "$mode" = check-bindings ]; then
    diff -u apple/Packages/RehaCore/Sources/RehaCore/RehaCore.swift "$generated/RehaCore.swift"
    diff -u apple/Packages/RehaCore/Headers/RehaCoreFFI.h "$generated/RehaCoreFFI.h"
    diff -u apple/Packages/RehaCore/Headers/module.modulemap "$generated/RehaCoreFFI.modulemap"
  else
    cp "$generated/RehaCore.swift" apple/Packages/RehaCore/Sources/RehaCore/
    cp "$generated/RehaCoreFFI.h" apple/Packages/RehaCore/Headers/
    cp "$generated/RehaCoreFFI.modulemap" apple/Packages/RehaCore/Headers/module.modulemap
  fi
  rm -rf "$generated"
}
framework() {
  bindings
  uv run scripts/fetch-models.py --tier small
  uv run scripts/fetch-ios-runtime.py
  python3 scripts/fetch-speech-model.py
  mkdir -p apple/build/ffi/device apple/build/ffi/simulator
  for variant in device simulator; do
    case "$variant" in
      device) triple=aarch64-apple-ios ;;
      simulator) triple=aarch64-apple-ios-sim ;;
    esac
    IPHONEOS_DEPLOYMENT_TARGET=26.0 cargo build --locked --release -p reha-ffi --lib --features onnx --target "$triple"
    xcrun libtool -static -o "apple/build/ffi/$variant/libRehaCoreFFI.a" \
      "target/$triple/release/libreha_ffi.a" "models/private/runtime/$triple/libonnxruntime.a"
    xcrun nm -g "apple/build/ffi/$variant/libRehaCoreFFI.a" 2>/dev/null | rg -q ' T _OrtGetApiBase$'
  done
  rm -rf apple/Packages/RehaCore/RehaCoreFFI.xcframework
  xcodebuild -create-xcframework \
    -library apple/build/ffi/device/libRehaCoreFFI.a -headers apple/Packages/RehaCore/Headers \
    -library apple/build/ffi/simulator/libRehaCoreFFI.a -headers apple/Packages/RehaCore/Headers \
    -output apple/Packages/RehaCore/RehaCoreFFI.xcframework
}
case "$mode" in
  bindings|check-bindings) bindings ;;
  integration) sh scripts/test-native-bindings.sh ;;
  framework) framework ;;
  simulator|device|archive|test)
    framework
    xcodegen generate --spec apple/project.yml --project apple
    case "$mode" in
      simulator) xcodebuild -project apple/Termine.xcodeproj -scheme Termine -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath apple/build/DerivedData CODE_SIGNING_ALLOWED=NO build ;;
      device) xcodebuild -project apple/Termine.xcodeproj -scheme Termine -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath apple/build/DerivedData CODE_SIGNING_ALLOWED=NO build ;;
      archive) xcodebuild -project apple/Termine.xcodeproj -scheme Termine -configuration Release -destination 'generic/platform=iOS' -archivePath apple/build/Laßnitzhöhe.xcarchive -allowProvisioningUpdates archive
        python3 scripts/package-native.py ;;
      test)
        xcodebuild -project apple/Termine.xcodeproj -scheme Termine -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath apple/build/DerivedData CODE_SIGNING_ALLOWED=NO build
        sh scripts/test-native-ui.sh --built ;;
    esac ;;
  *) echo 'Usage: scripts/build-native.sh bindings|check-bindings|integration|framework|simulator|device|archive|test' >&2; exit 2 ;;
esac
