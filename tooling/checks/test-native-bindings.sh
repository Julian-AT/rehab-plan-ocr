#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
eval "$(python3 tooling/dev/workspace.py shell)"
export CARGO_PROFILE_DEV_DEBUG=0
export CARGO_INCREMENTAL=0
cargo build --locked -p reha-ffi --features bindgen
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
"$CARGO_TARGET_DIR/debug/reha-bindgen" generate --library "$CARGO_TARGET_DIR/debug/libreha_ffi.dylib" --language swift --metadata-no-deps --no-format --out-dir "$output"
swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
  -I "$output" -Xcc -fmodule-map-file="$output/RehaCoreFFI.modulemap" \
  "$output/RehaCore.swift" apps/ios/Tests/BindingProbe.swift \
  -L "$CARGO_TARGET_DIR/debug" -lreha_ffi -Xlinker -rpath -Xlinker "$CARGO_TARGET_DIR/debug" -o "$output/probe"
cargo run --locked --quiet -p reha-ffi --example seed_fixture -- "$output/store"
"$output/probe" "$output/store"
