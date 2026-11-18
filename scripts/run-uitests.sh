#!/bin/sh
# Runs the UI tests in a simulator. They drive the app in the demo account, so they need neither an account nor
# the network.
#
#   scripts/run-uitests.sh [iPad|iPhone]
#
# SIMULATOR       name of the simulator to use (default: one of that kind on the newest iOS installed)
# SCREENSHOT_DIR  a folder for the tests' screenshots, in portrait and landscape (default: none taken)
set -eu

cd "$(dirname "$0")/.."

KIND="${1:-iPad}"
DEVICE="$(scripts/simulator-id.sh "$KIND")"
[ -n "$DEVICE" ] || { echo "Running the UI tests failed: no $KIND simulator is installed." >&2; exit 1; }
echo "Running the UI tests on $KIND simulator $DEVICE..."

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
STATUS=0
# xcodebuild hands TEST_RUNNER_-prefixed variables to the test runner without the prefix.
TEST_RUNNER_SCREENSHOT_DIR="${SCREENSHOT_DIR:-}" xcodebuild test -project ios/CharacterKeeper.xcodeproj -scheme CharacterKeeper-iOS \
    -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath ios/build > "$LOG" 2>&1 || STATUS=$?
grep -E " error: |Test Case .*(passed|failed)|\*\* TEST" "$LOG" || tail -n 20 "$LOG"
exit "$STATUS"
