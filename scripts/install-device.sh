#!/bin/sh
# Builds the iOS app, installs it on a connected iPhone or iPad and starts it.
#
# The device must be connected by cable or on the same network, unlocked, with Developer Mode on.
# Your Apple developer team goes in ios/Local.xcconfig (see ios/Signing.xcconfig).
#
# DEVICE        name of the iPhone or iPad to install on (default: the first one connected)
# DEVICE_LAUNCH "no" to leave the app closed after installing, as a scheduled reinstall does
set -eu

cd "$(dirname "$0")/.."

DEVICE_LIST="$(mktemp)"
BUILD_LOG="$(mktemp)"
trap 'rm -f "$DEVICE_LIST" "$BUILD_LOG"' EXIT
xcrun devicectl list devices --json-output "$DEVICE_LIST" >/dev/null

DEVICE="${DEVICE:-$(/usr/bin/python3 - "$DEVICE_LIST" <<'PYTHON'
import json
import sys

devices = json.load(open(sys.argv[1]))["result"]["devices"]
devices_found = [
    device["deviceProperties"]["name"] for device in devices
    if device.get("hardwareProperties", {}).get("deviceType") in ("iPad", "iPhone")
    and device.get("connectionProperties", {}).get("tunnelState") != "unavailable"
]
print(devices_found[0] if devices_found else "")
PYTHON
)}"
[ -n "$DEVICE" ] || { echo "Installing failed: no iPhone or iPad is connected." >&2; exit 1; }

BUNDLE_ID="$(xcodebuild -project ios/CharacterKeeper.xcodeproj -scheme CharacterKeeper-iOS \
    -showBuildSettings 2>/dev/null | sed -n 's/^ *PRODUCT_BUNDLE_IDENTIFIER = //p' | head -n 1)"

echo "Building for ${DEVICE}..."
# A failed build must stop here: the app left by an earlier build would install with its old signature.
if ! xcodebuild -project ios/CharacterKeeper.xcodeproj -scheme CharacterKeeper-iOS \
    -destination 'generic/platform=iOS' -derivedDataPath ios/build -allowProvisioningUpdates build \
    >"$BUILD_LOG" 2>&1; then
    grep -E 'error:' "$BUILD_LOG" >&2 || tail -n 20 "$BUILD_LOG" >&2
    echo "Installing failed: the build failed." >&2
    exit 1
fi
grep -E 'warning: .*[Pp]rovision|BUILD' "$BUILD_LOG" || true

APP="ios/build/Build/Products/Debug-iphoneos/Character Keeper.app"
[ -d "$APP" ] || { echo "Installing failed: the build did not produce the app." >&2; exit 1; }

xcrun devicectl device install app --device "$DEVICE" "$APP" >/dev/null
echo "Installed on $DEVICE."
[ "${DEVICE_LAUNCH:-yes}" = no ] && exit 0

if LAUNCH="$(xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" 2>&1)"; then
    echo "Started the app."
elif echo "$LAUNCH" | grep -q "not been explicitly trusted"; then
    cat >&2 <<'MESSAGE'
Starting the app failed: the device does not trust your developer profile yet.
On the device open Settings > General > VPN & Device Management, tap your Apple ID
under Developer App and tap Trust. Then open the app from the Home Screen.
MESSAGE
    exit 1
else
    echo "Starting the app failed:" >&2
    echo "$LAUNCH" | tail -n 5 >&2
    exit 1
fi
