.PHONY: build test lint coverage app run install dmg appstore icon artwork covers simulator uitest archive clean

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

# Builds the iPad app and starts it in a simulator (see scripts/run-simulator.sh).
simulator:
	scripts/run-simulator.sh

# Runs the iPad UI tests in a simulator, against the demo account.
uitest:
	scripts/run-uitests.sh

# Archives the iPhone and iPad app for the App Store into build/ChronicleKeeper.xcarchive, versioned from git.
archive:
	scripts/archive-ios.sh

clean:
	rm -rf .build build ios/build
