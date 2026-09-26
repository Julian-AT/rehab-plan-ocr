#!/bin/sh
# Builds a local iOS archive. No publication or profile creation is performed.
set -eu
cd "$(dirname "$0")/.."
export IPHONEOS_DEPLOYMENT_TARGET=17.0
export PATH="$HOME/.cargo/bin:$PATH"
uv run scripts/fetch-ios-runtime.py
case "${1:-simulator}" in
  simulator)
    node_modules/.bin/tauri ios build --target aarch64-sim --debug --ci --no-sign --archive-only --features ios-onnx -- --no-default-features
    ;;
  device)
    node_modules/.bin/tauri ios build --target aarch64 --ci --no-sign --archive-only --features ios-onnx -- --no-default-features
    ;;
  *) echo 'Usage: sh scripts/build-ios.sh simulator|device' >&2; exit 1 ;;
esac
