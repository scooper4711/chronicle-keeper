.PHONY: build test lint coverage app run install dmg icon covers simulator uitest clean

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

# Redraws Resources/AppIcon.icns from scripts/make-icon.swift.
icon:
	scripts/make-icon.sh

# Rewrites the table of covers the app ships with, from Warhorn's catalog (see scripts/update-adventure-covers.sh).
covers:
	scripts/update-adventure-covers.sh

# Builds the iPad app and starts it in a simulator (see scripts/run-simulator.sh).
simulator:
	scripts/run-simulator.sh

# Runs the iPad UI tests in a simulator, against the demo account.
uitest:
	scripts/run-uitests.sh

clean:
	rm -rf .build build ios/build
