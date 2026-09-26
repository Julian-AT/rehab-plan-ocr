#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
export PATH="$HOME/.cargo/bin:$PATH"
export CARGO_PROFILE_DEV_DEBUG=0
export CARGO_INCREMENTAL=0
cargo build --locked -p reha-ffi --features bindgen
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
target/debug/reha-bindgen generate --library target/debug/libreha_ffi.dylib --language swift --metadata-no-deps --no-format --out-dir "$output"
swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
  -I "$output" -Xcc -fmodule-map-file="$output/RehaCoreFFI.modulemap" \
  "$output/RehaCore.swift" apps/ios/Tests/BindingProbe.swift \
  -L target/debug -lreha_ffi -Xlinker -rpath -Xlinker "$PWD/target/debug" -o "$output/probe"
cargo run --locked --quiet -p reha-ffi --example seed_fixture -- "$output/store"
"$output/probe" "$output/store"
