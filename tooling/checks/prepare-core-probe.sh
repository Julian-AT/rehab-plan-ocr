#!/bin/sh
# Sourced by probes after changing to the source root.
eval "$(python3 tooling/dev/workspace.py shell)"
export CARGO_PROFILE_DEV_DEBUG=0 CARGO_INCREMENTAL=0
cargo build --locked -p reha-ffi
probe=$(mktemp -d)
trap 'rm -r "$probe"' EXIT
swiftc -j "${CARGO_BUILD_JOBS:-1}" -swift-version 6 -emit-library -emit-module -module-name RehaCore \
  -module-cache-path "$probe/cache" -emit-module-path "$probe/RehaCore.swiftmodule" \
  -I packages/apple/RehaCore/Headers packages/apple/RehaCore/Sources/RehaCore/RehaCore.swift \
  -L "$CARGO_TARGET_DIR/debug" -lreha_ffi -Xlinker -rpath -Xlinker "$CARGO_TARGET_DIR/debug" \
  -o "$probe/libRehaCore.dylib"
