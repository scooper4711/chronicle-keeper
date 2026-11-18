#!/bin/sh
# Builds the iPhone and iPad app for the simulator, installs it and starts it.
#
#   scripts/run-simulator.sh [iPad|iPhone] [app arguments, such as -demo]
#
# SIMULATOR  name of the simulator to use (default: one of that kind on the newest iOS installed)
set -eu

cd "$(dirname "$0")/.."

KIND="${1:-iPad}"
[ $# -gt 0 ] && shift
DEVICE="$(scripts/simulator-id.sh "$KIND")"
[ -n "$DEVICE" ] || { echo "Starting the simulator failed: no $KIND simulator is installed." >&2; exit 1; }

xcodebuild -project ios/ChronicleKeeper.xcodeproj -scheme ChronicleKeeper-iOS \
    -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath ios/build \
    CODE_SIGNING_ALLOWED=NO build | tail -n 3

APP="ios/build/Build/Products/Debug-iphonesimulator/Chronicle Keeper.app"
xcrun simctl boot "$DEVICE" 2>/dev/null || true
# Xcode 27 shows simulators in Device Hub; earlier versions in the Simulator app.
open -b com.apple.dt.Devices 2>/dev/null || open -a Simulator
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl launch --terminate-running-process "$DEVICE" io.github.scooper4711.ChronicleKeeper "$@"
