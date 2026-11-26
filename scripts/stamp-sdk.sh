#!/bin/sh
# Writes the version of the SDK a Mac binary was built with into the binary, where the build left something else.
#
# Swift Build, the default build engine of `swift build` from Xcode 27 on, writes the deployment target (14.0) where
# the SDK's version belongs. macOS reads that number to choose how an app looks and behaves, and takes 14.0 to mean
# an app from before the current design: it gets the old flat toolbar, whose buttons then keep the dimmed look of a
# background window after the app has come to the front, as if they were disabled. The older build engine wrote
# the SDK's version, as Xcode does, and a binary that already says it is left alone.
#
# Usage: scripts/stamp-sdk.sh <binary>   (before signing: the change invalidates a signature)
set -eu

BINARY="$1"
SDK="$(xcrun --sdk macosx --show-sdk-version)"
# One "minos" and one "sdk" line for each architecture, the same in all of them.
MINIMUM="$(xcrun vtool -show-build "$BINARY" | awk '$1 == "minos" { print $2; exit }')"
STAMPED="$(xcrun vtool -show-build "$BINARY" | awk '$1 == "sdk" { print $2; exit }')"
[ -n "$MINIMUM" ] || { echo "Stamping the SDK failed: $BINARY has no build version." >&2; exit 1; }
[ "$STAMPED" = "$SDK" ] && exit 0

# vtool warns that the signature will be invalid, which is expected here: the app is signed afterward.
xcrun vtool -set-build-version macos "$MINIMUM" "$SDK" -replace -output "$BINARY.stamped" "$BINARY" 2>/dev/null \
    || { echo "Stamping the SDK failed: vtool couldn't rewrite $BINARY." >&2; exit 1; }
mv "$BINARY.stamped" "$BINARY"
echo "Stamped SDK $SDK on $(basename "$BINARY"), which said $STAMPED."
