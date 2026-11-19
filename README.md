# Chronicle Keeper

[![CI](https://github.com/scooper4711/chronicle-keeper/actions/workflows/ci.yml/badge.svg)](https://github.com/scooper4711/chronicle-keeper/actions/workflows/ci.yml)
[![GitHub Release](https://img.shields.io/github/v/release/scooper4711/chronicle-keeper)](https://github.com/scooper4711/chronicle-keeper/releases)
[![Platforms](https://img.shields.io/badge/platforms-macOS%2014%2B%20%7C%20iPadOS%2017%2B%20%7C%20iOS%2017%2B-informational)](#requirements)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)

Paizo's My Organized Play page lists your characters, but it doesn't show their XP or level, hides each character's
sessions behind "Show Sessions" links, and doesn't help with slow track.

Chronicle Keeper is an unofficial app for the Mac, the iPad and the iPhone that signs in to paizo.com, reads your
Sessions and Summary tabs, and keeps a record of every character in every campaign: the adventures played, faction
reputation and Fame, and XP and level. It is free and open source, and it reads only your own account.

## Features

- Characters for Pathfinder Society (second and first edition) and Starfinder Society (second and first edition),
  with level, XP and a progress bar in every overview.
- XP inferred from each adventure's kind and the track (normal or slow) its reputation implies. Override the track
  for any session; the app shows why it chose each one.
- Starting level (1st, 3rd, 5th or 7th in second edition), default track per campaign, notes, a portrait and a
  link to the character sheet.
- Faction reputation and Fame as Paizo reports them (not shown for Starfinder Society second edition, which has no
  factions).
- Every session in full: tap an adventure for its details spelled out, with its cover and your chronicle sheet
  attached below.
- "Who can play...?": search every Organized Play adventure Paizo has published, by code or title, in
  [Warhorn](https://warhorn.net)'s catalog, and see which characters haven't played it and are in its level range.
- Boons: downloads the PDFs from the Boons tab for each character.
- Your own data syncs between your devices through iCloud (in builds that turn it on).
- A demo account with fictional characters, for trying the app without signing in.

## Requirements

macOS 14 or later, iPadOS 17 or later, or iOS 17 or later.

## Installing a release

Download the disk image from the [releases page](https://github.com/scooper4711/chronicle-keeper/releases), open it
and drag Chronicle Keeper to Applications.

## Building

You need Xcode 26 and [SwiftLint](https://github.com/realm/SwiftLint) (`brew install swiftlint`).

```sh
make test       # swift test
make lint       # swiftlint --strict
make coverage   # fails below 80% of the lines or regions of ChronicleKeeperKit
make run        # builds "build/Chronicle Keeper.app" (signed ad hoc without a Developer ID) and opens it
make dmg        # packages the disk image
make simulator  # the iPad app in a simulator
make uitest     # the iPad UI tests, against the demo account
```

Launch with `-demo` to open the demo account: `open "build/Chronicle Keeper.app" --args -demo`.

## Documentation

[CONTRIBUTING.md](CONTRIBUTING.md) explains how to contribute. [PRIVACY.md](PRIVACY.md) says what the app does with
your data (it keeps your password in the Keychain, your data on your device, and sends only the names of adventures anywhere but paizo.com). The
requirements and design are in [docs/specs/chronicle-keeper/](docs/specs/chronicle-keeper/).

## Licenses

Chronicle Keeper is under the [MIT License](LICENSE). Third-party software is listed in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## Community Use Policy

> Chronicle Keeper uses trademarks and/or copyrights owned by Paizo Inc.,
> used under Paizo's Community Use Policy
> ([paizo.com/licenses/communityuse](https://paizo.com/licenses/communityuse)).
> We are expressly prohibited from charging you to use or access this content.
> Chronicle Keeper is not published, endorsed, or specifically approved by
> Paizo. For more information about Paizo Inc. and Paizo products, visit
> [paizo.com](https://paizo.com).
