.PHONY: build test lint coverage app run install dmg appstore icon artwork covers items simulator uitest archive clean

build:
	swift build

test:
	swift test

lint:
	swiftlint --strict --quiet

coverage:
	scripts/coverage.sh

app:
	scripts/build-app.sh

run: app
	open "build/Chronicle Keeper.app"

# Copies the built app into /Applications, replacing an earlier copy.
install: app
	rm -rf "/Applications/Chronicle Keeper.app"
	ditto "build/Chronicle Keeper.app" "/Applications/Chronicle Keeper.app"

dmg: app
	scripts/make-dmg.sh

# Builds the Mac App Store package, build/appstore/Chronicle Keeper.pkg (see scripts/build-app.sh for the variables).
appstore:
	swift package resolve
	CHANNEL=appstore scripts/build-app.sh

# Redraws Resources/AppIcon.icns from scripts/make-icon.swift.
icon:
	scripts/make-icon.sh

# Writes the Rexard art into the package's resources, from the private Artwork submodule or the full packs
# (see scripts/add-artwork.sh). The app and archive builds do this themselves.
artwork:
	scripts/add-artwork.sh

# Rewrites the table of covers the app ships with, from Warhorn's catalog (see scripts/update-adventure-covers.sh).
covers:
	scripts/update-adventure-covers.sh

# Writes the item price list the purchase ledger searches, from pf2e.release (see scripts/import-items.sh).
items:
	scripts/import-items.sh

# Builds the iPad app and starts it in a simulator (see scripts/run-simulator.sh).
simulator:
	scripts/run-simulator.sh

# Runs the iPad UI tests in a simulator, against the demo account.
uitest:
	scripts/run-uitests.sh

# Archives the app for the App Store and exports build/ipad/export/*.ipa, versioned from git. Upload it with
# `make testflight`.
.PHONY: ipad-archive testflight
ipad-archive:
	scripts/add-artwork.sh
	scripts/import-items.sh
	.build/checkouts/tabletop-kit/scripts/archive-ios.sh ios/ChronicleKeeper.xcodeproj ChronicleKeeper-iOS build/ipad

# Uploads the newest build (the .ipa from ipad-archive or the .pkg from appstore) to TestFlight, with this release's
# notes from the tableside-store checkout next to this repository (TABLESIDE_STORE).
TABLESIDE_STORE ?= ../tableside-store
TESTFLIGHT_NOTES = $(TABLESIDE_STORE)/chronicle-keeper/testflight/what-to-test.txt
TESTFLIGHT_BUILD ?= $(shell ls -t build/ipad/export/*.ipa build/appstore/*.pkg 2>/dev/null | head -n 1)
testflight:
	@test -f "$(TESTFLIGHT_NOTES)" || { echo "testflight failed: $(TESTFLIGHT_NOTES) not found; set TABLESIDE_STORE"; exit 1; }
	@test -n "$(TESTFLIGHT_BUILD)" || { echo "testflight failed: no build; run make ipad-archive or make appstore"; exit 1; }
	.build/checkouts/tabletop-kit/scripts/testflight.sh io.github.scooper4711.ChronicleKeeper "$(TESTFLIGHT_BUILD)" "$(TESTFLIGHT_NOTES)"

# The old name of ipad-archive.
archive: ipad-archive

clean:
	rm -rf .build build ios/build
