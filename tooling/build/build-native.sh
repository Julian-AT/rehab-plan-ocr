#!/bin/sh
# Reproducible native build. Signing and installation are explicit modes only.
set -eu
cd "$(dirname "$0")/../.."
eval "$(python3 tooling/dev/workspace.py shell)"
export CARGO_PROFILE_DEV_DEBUG=0 CARGO_INCREMENTAL=0
mode=${1:-simulator}
if [ "$mode" = archive ]; then
  : "${RELEASE_RUN:?Set RELEASE_RUN to a new directory below .local/releases}"
  archive_path=$(python3 tooling/release/release_artifacts.py "$RELEASE_RUN")
fi
bindings() {
  cargo build --locked --offline -p reha-ffi --features bindgen
  generated=$(mktemp -d)
  "$CARGO_TARGET_DIR/debug/reha-bindgen" generate "$CARGO_TARGET_DIR/debug/libreha_ffi.dylib" --language swift --metadata-no-deps --no-format --out-dir "$generated"
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
  python3 tooling/release/runtime_inventory.py verify
  python3 tooling/dev/quality.py space 2
  bindings
  case "$mode" in
    simulator | test) variants=simulator ;;
    device) variants=device ;;
    *) variants='device simulator' ;;
  esac
  for variant in $variants; do
    python3 tooling/build/verify-native-assets.py "$variant"
  done
  for variant in $variants; do
    case "$variant" in
      device) triple=aarch64-apple-ios ;;
      simulator) triple=aarch64-apple-ios-sim ;;
    esac
    python3 tooling/dev/quality.py space 1.5
    IPHONEOS_DEPLOYMENT_TARGET=26.0 cargo build --locked --offline --release -p reha-ffi --lib --features onnx --target "$triple"
  done
  # Split only our fixed variant names; never interpolate paths or user commands.
  # shellcheck disable=SC2086
  python3 tooling/build/assemble-native.py $variants
  for variant in $variants; do
    if [ "${REHA_LOW_DISK:-0}" = 1 ]; then
      case "$variant" in
        device) triple=aarch64-apple-ios ;;
        simulator) triple=aarch64-apple-ios-sim ;;
      esac
      rm -r "$CARGO_TARGET_DIR/$triple/release"
    fi
  done
}
case "$mode" in
  bindings | check-bindings) bindings ;;
  integration) sh tooling/checks/test-native-bindings.sh ;;
  framework) framework ;;
  simulator | device | archive | test)
    framework
    xcodegen generate --spec apps/ios/project.yml --project apps/ios
    case "$mode" in
      simulator) xcodebuild -project apps/ios/Termine.xcodeproj -scheme Termine -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath "$REHA_IOS_BUILD_DIR/DerivedData" ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build ;;
      device) xcodebuild -project apps/ios/Termine.xcodeproj -scheme Termine -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$REHA_IOS_BUILD_DIR/DerivedData" ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build ;;
      archive)
        xcodebuild -project apps/ios/Termine.xcodeproj -scheme Termine -configuration Release -destination 'generic/platform=iOS' -archivePath "$archive_path" ARCHS=arm64 -allowProvisioningUpdates archive
        python3 tooling/release/package-native.py --run "$RELEASE_RUN"
        ;;
      test)
        xcodebuild -project apps/ios/Termine.xcodeproj -scheme Termine -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath "$REHA_IOS_BUILD_DIR/DerivedData" ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build
        sh tooling/checks/test-native-ui.sh --built
        ;;
    esac
    ;;
  *)
    echo 'Usage: tooling/build/build-native.sh bindings|check-bindings|integration|framework|simulator|device|archive|test' >&2
    exit 2
    ;;
esac
