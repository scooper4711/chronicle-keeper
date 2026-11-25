#!/bin/sh
# Builds "build/Chronicle Keeper.app" from the Swift package, signed with the Developer ID in the keychain, or ad hoc
# without one.
#
# VERSION       version written to the bundle (default: scripts/version.sh marketing)
# BUILD_NUMBER  CFBundleVersion (default: scripts/version.sh build)
# UNIVERSAL     set to 1 to build for both Apple silicon and Intel
# SIGNING_IDENTITY  passed to scripts/sign-app.sh; "-" signs ad hoc
# TEAM_ID       team the app is signed for (default: the team of the Developer ID certificate in the keychain; none
#               when signing ad hoc)
# PROVISIONING_PROFILE  Developer ID provisioning profile with iCloud; with a team, the app syncs the user's own data
#               through iCloud (scripts/add-icloud-entitlements.sh, which ICLOUD_ENVIRONMENT also affects). Without
#               one the app keeps its data on this Mac, as macOS stops an app that claims iCloud with no profile.
# CHANNEL       "appstore" also builds the Mac App Store package, build/appstore/Chronicle Keeper.pkg, from the same
#               sources, compiled with -DAPP_STORE; PROVISIONING_PROFILE is then the Mac App Store profile (with
#               iCloud), and the variables of tabletop-kit's scripts/package-appstore.sh are needed (PACKAGER names
#               another copy; TRIAL=1 checks the package without them).
# REXARD_PACKS  folder of Rexard packs the app's art must come from (scripts/add-artwork.sh)
set -eu

cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(scripts/version.sh marketing)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(scripts/version.sh build)}"
APP="build/Chronicle Keeper.app"
EXECUTABLE="ChronicleKeeper"

# The Rexard art, where this checkout has it (REXARD_PACKS makes it required).
scripts/add-artwork.sh

# The item prices the purchase ledger searches. A store build always imports them and fails without them. Other
# builds reuse a list newer than pf2e.release (`make items` imports it again), and build without one if the import
# can't run (no network, say).
ITEMS=Sources/ChronicleKeeperKit/Resources/Items/items.json
if [ "${CHANNEL:-}" = "appstore" ]; then
    scripts/import-items.sh
elif [ -f "$ITEMS" ] && [ "$ITEMS" -nt pf2e.release ]; then
    echo "Using the item price list from $(date -r "$ITEMS" '+%Y-%m-%d %H:%M'); make items imports it again."
else
    scripts/import-items.sh || echo "Warning: no item price list; the ledger can't suggest items." >&2
fi

SWIFT_FLAGS=""
[ "${CHANNEL:-}" = "appstore" ] && SWIFT_FLAGS="-Xswiftc -DAPP_STORE"

if [ "${UNIVERSAL:-0}" = "1" ]; then
    # shellcheck disable=SC2086 # SWIFT_FLAGS is a list of words
    swift build -c release $SWIFT_FLAGS --arch arm64 --arch x86_64
    # Asked rather than assumed: newer SwiftPM moved universal builds out of .build/apple.
    BINARY="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$EXECUTABLE"
else
    # shellcheck disable=SC2086
    swift build -c release $SWIFT_FLAGS
    BINARY="$(swift build -c release --show-bin-path)/$EXECUTABLE"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$EXECUTABLE"
# The packages' resources are bundles beside the executable; Bundle.module looks for them in Resources.
for bundle in "$(dirname "$BINARY")"/*.bundle; do
    # The test target's fixtures stay out of the app.
    case "$bundle" in *Tests.bundle) continue ;; esac
    [ -d "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp ios/App/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Chronicle Keeper</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.scooper4711.ChronicleKeeper</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Chronicle Keeper</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Stephen Cooper. MIT License.</string>
</dict>
</plist>
PLIST

# The entitlements turn on the App Sandbox. iCloud is added only to a build signed by the team with a provisioning
# profile that allows it: an ad hoc signature can't carry it, and the Info.plist names the container only then.
[ "${SIGNING_IDENTITY:-}" = "-" ] && TEAM_ID="${TEAM_ID:-none}"
TEAM_ID="${TEAM_ID:-$(security find-identity -v -p codesigning \
    | sed -n 's/.*"Developer ID Application: .*(\([A-Z0-9]*\))"$/\1/p' | head -n 1)}"
ENTITLEMENTS="build/ChronicleKeeper.entitlements"
cp Resources/ChronicleKeeper.entitlements "$ENTITLEMENTS"
if [ -n "$TEAM_ID" ] && [ "$TEAM_ID" != "none" ] && [ -n "${PROVISIONING_PROFILE:-}" ]; then
    scripts/add-icloud-entitlements.sh "$APP" "$ENTITLEMENTS" "$TEAM_ID" "$PROVISIONING_PROFILE"
fi
scripts/sign-app.sh "$APP" "$ENTITLEMENTS"
echo "Built $APP ($VERSION, build $BUILD_NUMBER)"

if [ "${CHANNEL:-}" = "appstore" ]; then
    # The packager reads both from the environment; here they may have come from git and the keychain.
    export BUILD_NUMBER TEAM_ID
    # Found beside the package after "swift package resolve", so the script follows the dependency pin.
    "${PACKAGER:-.build/checkouts/tabletop-kit/scripts/package-appstore.sh}" "$APP" "$ENTITLEMENTS" \
        io.github.scooper4711.ChronicleKeeper
fi
