#!/bin/sh
# Builds a local iOS archive. No publication or profile creation is performed.
set -eu
cd "$(dirname "$0")/.."
export IPHONEOS_DEPLOYMENT_TARGET=17.0
export PATH="$HOME/.cargo/bin:$PATH"
node scripts/sync-ios-project.mjs
uv run scripts/fetch-ios-runtime.py
case "${1:-simulator}" in
  simulator)
    node_modules/.bin/tauri ios build --target aarch64-sim --debug --ci --no-sign --archive-only --features ios-onnx -- --no-default-features
    # Keep App Group access and extension identity in simulator acceptance runs.
    # Ad-hoc signing requires no development profile or physical device access.
    sim_app='src-tauri/gen/apple/build/reha-calendar_iOS.xcarchive/Products/Applications/Laßnitzhöhe.app'
    test "$(plutil -extract DTPlatformName raw -o - "$sim_app/Info.plist")" = iphonesimulator
    for extension in RehaWidgets RehaNotificationContent; do
      codesign --force --sign - --entitlements "src-tauri/gen/apple/$extension/$extension.entitlements" "$sim_app/PlugIns/$extension.appex"
    done
    codesign --force --sign - --entitlements src-tauri/gen/apple/reha-calendar_iOS/reha-calendar_iOS.entitlements "$sim_app"
    ;;
  device)
    node_modules/.bin/tauri ios build --target aarch64 --ci --no-sign --archive-only --features ios-onnx -- --no-default-features
    ;;
  *) echo 'Usage: sh scripts/build-ios.sh simulator|device' >&2; exit 1 ;;
esac
