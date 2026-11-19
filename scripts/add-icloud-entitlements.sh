#!/bin/sh
# Lets a Developer ID build of the Mac app use iCloud (docs/specs/chronicle-keeper/design.md, "Turning iCloud on").
# tabletop-kit's script of the same name adds the CloudKit container and push entitlements to the entitlements to
# sign with and embeds the provisioning profile that allows them. This adds what is Chronicle Keeper's own: iCloud
# Documents, which the boon and chronicle PDFs sync through, and in the Info.plist the container's name, which turns
# settings sync on, and its folder in iCloud Drive. It can run again on the same files.
#
# Usage: scripts/add-icloud-entitlements.sh <app> <entitlements> <team ID> <provisioning profile>
# ICLOUD_ENVIRONMENT  CloudKit environment, Production (default) or Development. An iPad or iPhone build installed
#                     from Xcode uses Development, so to sync with one, build the Mac app for Development too.
# KIT_SCRIPT          another copy of tabletop-kit's script (default: the one beside the resolved package)
set -eu

CONTAINER="iCloud.io.github.scooper4711.ChronicleKeeper"

if [ $# -ne 4 ]; then
    echo "Usage: $0 <app> <entitlements> <team ID> <provisioning profile>" >&2
    exit 2
fi
APP="$1"
ENTITLEMENTS="$2"

# Found beside the package after "swift package resolve", so the script follows the dependency pin.
ICLOUD_CONTAINERS="$CONTAINER" \
    "${KIT_SCRIPT:-.build/checkouts/tabletop-kit/scripts/add-icloud-entitlements.sh}" "$@"

# FileManager.url(forUbiquityContainerIdentifier: nil) takes the first of the ubiquity containers.
/usr/libexec/PlistBuddy -c "Delete :com.apple.developer.ubiquity-container-identifiers" "$ENTITLEMENTS" \
    >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy \
    -c "Add :com.apple.developer.icloud-services:1 string CloudDocuments" \
    -c "Add :com.apple.developer.ubiquity-container-identifiers array" \
    -c "Add :com.apple.developer.ubiquity-container-identifiers:0 string $CONTAINER" \
    "$ENTITLEMENTS"
INFO="$APP/Contents/Info.plist"
plutil -replace ChronicleKeeperContainer -string "$CONTAINER" "$INFO"

# Shows the container's Documents folder in iCloud Drive, as "Chronicle Keeper", with Boons and Chronicles in it.
# iCloud Drive reads this again only when CFBundleVersion grows. PlistBuddy, as plutil splits a key at its periods.
SHOWN=":NSUbiquitousContainers:$CONTAINER"
/usr/libexec/PlistBuddy -c "Delete :NSUbiquitousContainers" "$INFO" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy \
    -c "Add :NSUbiquitousContainers dict" \
    -c "Add $SHOWN dict" \
    -c "Add $SHOWN:NSUbiquitousContainerIsDocumentScopePublic bool true" \
    -c "Add $SHOWN:NSUbiquitousContainerName string Chronicle Keeper" \
    -c "Add $SHOWN:NSUbiquitousContainerSupportedFolderLevels string Any" \
    "$INFO"
echo "Added iCloud Documents for $CONTAINER"
