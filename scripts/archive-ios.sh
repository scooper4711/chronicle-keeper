#!/bin/sh
# Archives the iPhone and iPad app for the App Store into build/ChronicleKeeper.xcarchive. To upload it, open the
# archive, which shows it in Xcode's Organizer, and choose Distribute App > App Store Connect.
#
# Your Apple developer team goes in ios/Local.xcconfig (see ios/Signing.xcconfig).
#
# VERSION       version of the archive (default: scripts/version.sh marketing)
# BUILD_NUMBER  build number, which must grow with every upload (default: scripts/version.sh build)
# REXARD_PACKS  folder of Rexard packs the app's art must come from (scripts/add-artwork.sh)
set -eu

cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(scripts/version.sh marketing)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(scripts/version.sh build)}"
ARCHIVE="build/ChronicleKeeper.xcarchive"

scripts/add-artwork.sh
rm -rf "$ARCHIVE"
# The two settings on the command line win over ios/Version.xcconfig, which the scheme writes from git.
xcodebuild -project ios/ChronicleKeeper.xcodeproj -scheme ChronicleKeeper-iOS -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive -quiet
echo "Archived $ARCHIVE ($VERSION, build $BUILD_NUMBER)"
