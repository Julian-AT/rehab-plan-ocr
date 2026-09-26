#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
runtime=$(python3 tooling/checks/native-simulator.py --profile "${REHA_SIMULATOR_PROFILE:-local}")
event_simulator=$(xcrun simctl create "Calendar-Events-Test-$(date +%s)" com.apple.CoreSimulator.SimDeviceType.iPhone-17 "$runtime")
trap 'xcrun simctl shutdown "$event_simulator" >/dev/null 2>&1 || true; xcrun simctl delete "$event_simulator" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$event_simulator"
xcrun simctl bootstatus "$event_simulator" -b
xcodegen generate --spec apps/ios/IntegrationTests/project.yml --project apps/ios/IntegrationTests
xcodebuild -project apps/ios/IntegrationTests/RehaSmoke.xcodeproj -scheme RehaSmoke -configuration Debug -destination "platform=iOS Simulator,id=$event_simulator" -derivedDataPath apps/ios/build/EventTests CODE_SIGNING_ALLOWED=NO build-for-testing
runner=apps/ios/build/EventTests/Build/Products/Debug-iphonesimulator/RehaSmoke-Runner.app
if ! xcrun simctl install "$event_simulator" "$runner"; then
  # Fresh simulator icon/installation services may still be initializing.
  sleep 3
  xcrun simctl install "$event_simulator" "$runner"
fi
event_runner_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$runner/Info.plist")
xcrun simctl privacy "$event_simulator" grant calendar "$event_runner_id"
xcodebuild -project apps/ios/IntegrationTests/RehaSmoke.xcodeproj -scheme RehaSmoke -configuration Debug -destination "platform=iOS Simulator,id=$event_simulator" -derivedDataPath apps/ios/build/EventTests -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test-without-building
