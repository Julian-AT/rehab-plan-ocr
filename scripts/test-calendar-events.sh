#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
event_simulator=$(xcrun simctl create "Calendar-Events-Test-$(date +%s)" com.apple.CoreSimulator.SimDeviceType.iPhone-17)
trap 'xcrun simctl shutdown "$event_simulator" >/dev/null 2>&1 || true; xcrun simctl delete "$event_simulator" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$event_simulator"
xcrun simctl bootstatus "$event_simulator" -b
xcodegen generate --spec tests/ios/project.yml --project tests/ios
xcodebuild -project tests/ios/RehaSmoke.xcodeproj -scheme RehaSmoke -configuration Debug -destination "platform=iOS Simulator,id=$event_simulator" -derivedDataPath apple/build/EventTests CODE_SIGNING_ALLOWED=NO build-for-testing
runner=apple/build/EventTests/Build/Products/Debug-iphonesimulator/RehaSmoke-Runner.app
xcrun simctl install "$event_simulator" "$runner"
event_runner_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$runner/Info.plist")
xcrun simctl privacy "$event_simulator" grant calendar "$event_runner_id"
xcodebuild -project tests/ios/RehaSmoke.xcodeproj -scheme RehaSmoke -configuration Debug -destination "platform=iOS Simulator,id=$event_simulator" -derivedDataPath apple/build/EventTests -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO -only-testing:RehaSmoke/EventEditingTests -only-testing:RehaSmoke/AgendaNativeTests test-without-building
