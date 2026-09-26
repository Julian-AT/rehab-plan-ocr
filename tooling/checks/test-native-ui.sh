#!/bin/sh
# Uses a disposable simulator and only the public synthetic plan.
set -eu
cd "$(dirname "$0")/../.."
eval "$(python3 tooling/dev/workspace.py shell)"
export CARGO_PROFILE_DEV_DEBUG=0 CARGO_INCREMENTAL=0
runtime=$(python3 tooling/checks/native-simulator.py --profile "${REHA_SIMULATOR_PROFILE:-local}" --simulator "${REHA_TEST_SIMULATOR:-}")
if [ "${1:-}" = --built ]; then
  shift
  python3 tooling/build/product_generation.py check
else
  sh tooling/build/build-native.sh simulator
fi
# Build tests before signing the simulator copy. A subsequent `test` build would
# reinstall the unsigned product and lose its App Group entitlements.
python3 tooling/build/product_generation.py build -- xcodebuild -project apps/ios/Termine.xcodeproj -scheme Termine -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build-for-testing
if [ -n "${REHA_TEST_SIMULATOR:-}" ]; then
  simulator=$REHA_TEST_SIMULATOR
else
  simulator=$(xcrun simctl create "Termine-Native-Test-$(date +%s)" com.apple.CoreSimulator.SimDeviceType.iPhone-17 "$runtime")
fi
printf 'Simulator: %s\n' "$simulator"
staging=$(mktemp -d)
cleanup() {
  if [ "${REHA_KEEP_SIMULATOR:-0}" != 1 ] && [ -z "${REHA_TEST_SIMULATOR:-}" ]; then
    xcrun simctl shutdown "$simulator" > /dev/null 2>&1 || true
    xcrun simctl delete "$simulator" > /dev/null 2>&1 || true
  fi
  rm -rf "$staging"
}
trap cleanup EXIT INT TERM
xcrun simctl boot "$simulator" 2> /dev/null || true
xcrun simctl bootstatus "$simulator" -b
app="$staging/Laßnitzhöhe.app"
# File-provider metadata can reappear immediately under Documents. Sign a
# disposable local copy, as the private packaging verifier does.
cp -cRp "$REHA_IOS_BUILD_DIR/DerivedData"/Build/Products/Debug-iphonesimulator/Laßnitzhöhe.app "$app" || ditto "$REHA_IOS_BUILD_DIR/DerivedData"/Build/Products/Debug-iphonesimulator/Laßnitzhöhe.app "$app"
xattr -cr "$app"
codesign --force --sign - --entitlements apps/ios/Extensions/Widgets/Widgets.entitlements "$app/PlugIns/RehaWidgets.appex"
codesign --force --sign - --entitlements apps/ios/Extensions/NotificationContent/Notification.entitlements "$app/PlugIns/RehaNotificationContent.appex"
codesign --force --sign - --entitlements apps/ios/Extensions/Share/Share.entitlements "$app/PlugIns/RehaShare.appex"
codesign --force --sign - --entitlements apps/ios/App/Termine.entitlements "$app"
if ! xcrun simctl install "$simulator" "$app"; then
  # A freshly booted simulator can still be initializing its icon services.
  sleep 3
  xcrun simctl install "$simulator" "$app"
fi
container=$(xcrun simctl get_app_container "$simulator" at.rehakalender.personal data)
if [ -z "${REHA_TEST_SIMULATOR:-}" ]; then
  cargo run --locked --quiet -p reha-ffi --example seed_fixture -- "$container/Library/Application Support/at.rehakalender.personal" --ui
else
  printf 'Reusing synthetic test data in disposable simulator.\n'
fi
xcrun simctl privacy "$simulator" grant calendar at.rehakalender.personal
xcrun simctl privacy "$simulator" grant microphone at.rehakalender.personal
xcrun simctl privacy "$simulator" grant camera at.rehakalender.personal
# Targeted calendar/voice runs can omit the photo and Files picker fixtures.
if [ "${REHA_UI_MEDIA:-1}" != 0 ]; then
  xcrun simctl launch "$simulator" com.apple.DocumentsApp > /dev/null
  python3 - "$simulator" << 'PY'
import plistlib, shutil, sys
from pathlib import Path
groups = Path.home() / "Library/Developer/CoreSimulator/Devices" / sys.argv[1] / "data/Containers/Shared/AppGroup"
for metadata in groups.glob("*/.com.apple.mobile_container_manager.metadata.plist"):
    if plistlib.loads(metadata.read_bytes()).get("MCMMetadataIdentifier") == "group.com.apple.FileProvider.LocalStorage":
        folder = metadata.parent / "File Provider Storage"
        folder.mkdir(exist_ok=True)
        shutil.copy2("ml/evaluation/fixtures/synthetic-day.png", folder / "Testplan.png")
        break
else:
    raise RuntimeError("Test simulator has no local Files provider")
PY
  if [ "${REHA_UI_NEW_PHOTO:-0}" = 1 ]; then
    # Different source bytes exercise new recognition instead of duplicate reuse.
    sips -s format jpeg ml/evaluation/fixtures/synthetic-day.png --out "$staging/new-photo.jpg" > /dev/null
    xcrun simctl addmedia "$simulator" "$staging/new-photo.jpg"
  else
    xcrun simctl addmedia "$simulator" ml/evaluation/fixtures/synthetic-day.png
  fi
fi
python3 - "$staging" << 'PYRUN'
import os, plistlib, sys
from pathlib import Path
staging = Path(sys.argv[1])
products = (Path(os.environ["REHA_IOS_BUILD_DIR"]) / "DerivedData/Build/Products").resolve()
source = next(products.glob("Termine_iphonesimulator*.xctestrun"))
run = plistlib.loads(source.read_bytes())
def absolute(value):
    if isinstance(value, str):
        return value.replace("__TESTROOT__", str(products))
    if isinstance(value, list):
        return [absolute(v) for v in value]
    if isinstance(value, dict):
        return {k: absolute(v) for k, v in value.items()}
    return value
run = absolute(run)
for name, target in run.items():
    if name.startswith("__") or not isinstance(target, dict):
        continue
    target["UITargetAppPath"] = str(staging / "Laßnitzhöhe.app")
    target["DependentProductPaths"] = [
        str(staging / "Laßnitzhöhe.app") if Path(p).name == "Laßnitzhöhe.app" else p
        for p in target.get("DependentProductPaths", [])
    ]
(staging / "Termine.xctestrun").write_bytes(plistlib.dumps(run))
PYRUN
python3 tooling/checks/ui-test-result.py run -xctestrun "$staging/Termine.xctestrun" \
  -destination "platform=iOS Simulator,id=$simulator" \
  -parallel-testing-enabled NO "$@"
