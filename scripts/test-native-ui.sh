#!/bin/sh
# Uses a disposable simulator and only the public synthetic plan.
set -eu
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"
export CARGO_PROFILE_DEV_DEBUG=0 CARGO_INCREMENTAL=0
if [ "${1:-}" = --built ]; then shift; else sh scripts/build-native.sh simulator; fi
simulator=$(xcrun simctl create "Termine-Native-Test-$(date +%s)" com.apple.CoreSimulator.SimDeviceType.iPhone-17)
printf 'Simulator: %s\n' "$simulator"
staging=$(mktemp -d)
cleanup() {
  if [ "${REHA_KEEP_SIMULATOR:-0}" != 1 ]; then
    xcrun simctl shutdown "$simulator" >/dev/null 2>&1 || true
    xcrun simctl delete "$simulator" >/dev/null 2>&1 || true
  fi
  rm -rf "$staging"
}
trap cleanup EXIT INT TERM
xcrun simctl boot "$simulator"
xcrun simctl bootstatus "$simulator" -b
app="$staging/Laßnitzhöhe.app"
# File-provider metadata can reappear immediately under Documents. Sign a
# disposable local copy, as the private packaging verifier does.
ditto apple/build/DerivedData/Build/Products/Debug-iphonesimulator/Laßnitzhöhe.app "$app"
xattr -cr "$app"
codesign --force --sign - --entitlements apple/Extensions/Widgets.entitlements "$app/PlugIns/RehaWidgets.appex"
codesign --force --sign - --entitlements apple/Extensions/Notification.entitlements "$app/PlugIns/RehaNotificationContent.appex"
codesign --force --sign - --entitlements apple/ShareExtension/Share.entitlements "$app/PlugIns/RehaShare.appex"
codesign --force --sign - --entitlements apple/Termine/Termine.entitlements "$app"
if ! xcrun simctl install "$simulator" "$app"; then
  # A freshly booted simulator can still be initializing its icon services.
  sleep 3
  xcrun simctl install "$simulator" "$app"
fi
container=$(xcrun simctl get_app_container "$simulator" at.rehakalender.personal data)
cargo run --locked --quiet -p reha-ffi --example seed_fixture -- "$container/Library/Application Support/at.rehakalender.personal" --ui
xcrun simctl privacy "$simulator" grant calendar at.rehakalender.personal
xcrun simctl privacy "$simulator" grant microphone at.rehakalender.personal
xcrun simctl launch "$simulator" com.apple.DocumentsApp >/dev/null
python3 - "$simulator" <<'PY'
import plistlib, shutil, sys
from pathlib import Path
groups = Path.home() / "Library/Developer/CoreSimulator/Devices" / sys.argv[1] / "data/Containers/Shared/AppGroup"
for metadata in groups.glob("*/.com.apple.mobile_container_manager.metadata.plist"):
    if plistlib.loads(metadata.read_bytes()).get("MCMMetadataIdentifier") == "group.com.apple.FileProvider.LocalStorage":
        folder = metadata.parent / "File Provider Storage"
        folder.mkdir(exist_ok=True)
        shutil.copy2("public/synthetic-day.png", folder / "Testplan.png")
        break
else:
    raise RuntimeError("Test simulator has no local Files provider")
PY
if [ "${REHA_UI_NEW_PHOTO:-0}" = 1 ]; then
  # Different source bytes exercise new recognition instead of duplicate reuse.
  sips -s format jpeg public/synthetic-day.png --out "$staging/new-photo.jpg" >/dev/null
  xcrun simctl addmedia "$simulator" "$staging/new-photo.jpg"
else
  xcrun simctl addmedia "$simulator" public/synthetic-day.png
fi
xcodebuild -project apple/Termine.xcodeproj -scheme Termine -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath apple/build/DerivedData \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO "$@" test
