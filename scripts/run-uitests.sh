#!/bin/sh
# Runs the UI tests in a simulator. They drive the app in the demo account, so they need neither an account nor
# the network.
#
#   scripts/run-uitests.sh [iPad|iPhone]
#
# Each run drives a simulator of its own: a copy of the one chosen, erased first and deleted afterward. A simulator
# that is used again keeps what earlier runs saved, and the Mac mini that runs CI runs two jobs at once, which
# would otherwise share one simulator.
#
# SIMULATOR       name of the simulator to copy (default: one of that kind on the newest iOS installed)
# SCREENSHOT_DIR  a folder for the tests' screenshots, in portrait and landscape (default: none taken)
#
# The run's result bundle, with each test's screen recording, is kept at ios/build/UITests.xcresult. When the run
# fails, xcodebuild's own reasons are printed: a test that never reports, because the app or the runner died, is
# named only there.
set -eu

cd "$(dirname "$0")/.."

KIND="${1:-iPad}"
SOURCE="$(scripts/simulator-id.sh "$KIND")"
[ -n "$SOURCE" ] || { echo "Running the UI tests failed: no $KIND simulator is installed." >&2; exit 1; }
DEVICE="$(xcrun simctl clone "$SOURCE" "UI tests $$")" \
    || { echo "Running the UI tests failed: simulator $SOURCE couldn't be copied (is it booted?)." >&2; exit 1; }
LOG="$(mktemp)"
RESULT=ios/build/UITests.xcresult
rm -rf "$RESULT"
remove_copy() {
    xcrun simctl shutdown "$DEVICE" >/dev/null 2>&1 || true
    xcrun simctl delete "$DEVICE" >/dev/null 2>&1 || true
    rm -f "$LOG"
}
trap remove_copy EXIT
trap 'exit 1' INT TERM
xcrun simctl erase "$DEVICE"
echo "Running the UI tests on $KIND simulator $DEVICE, a fresh copy of $SOURCE..."

STATUS=0
# xcodebuild hands TEST_RUNNER_-prefixed variables to the test runner without the prefix.
TEST_RUNNER_SCREENSHOT_DIR="${SCREENSHOT_DIR:-}" xcodebuild test -project ios/ChronicleKeeper.xcodeproj -scheme ChronicleKeeper-iOS \
    -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath ios/build -resultBundlePath "$RESULT" \
    > "$LOG" 2>&1 || STATUS=$?
grep -E " error: |Test Case .*(passed|failed)|\*\* TEST" "$LOG" || tail -n 20 "$LOG"
if [ "$STATUS" -ne 0 ]; then
    echo "Why the run failed, as xcodebuild tells it:"
    sed -n '/^Failing tests:/,/^\*\* TEST/p; /^Testing failed:/,/^\*\* TEST/p' "$LOG" | head -n 60
fi
exit "$STATUS"
