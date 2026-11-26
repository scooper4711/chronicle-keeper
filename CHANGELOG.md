# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- A gold and purchases ledger for each character, laid out as a spreadsheet, with amounts in gold pieces
- Ledger groups have titles, and a picked item's price can be overridden; a name nothing matches is a custom item
  with its own price
- Item prices from the pf2e data, for picking purchases
- The demo characters have ledgers
- An adventure's kind and XP show under its title
- Each faction shows the status the character's reputation has earned (Liked, Admired, Revered, or the Starfinder
  tier), and how much the next one still needs
- A sparkle shows where a free Chronicle Boon or Game Reward is waiting to be claimed on paizo.com: beside the
  adventure, on the faction, in the sidebar and in a "Ready to Claim" list at the top of Boons
- A purchase marked as maybe not Society legal can be linked to the boon or the Chronicle Sheet that allows it,
  yours or another character's, which turns its warning into a green check

### Fixed
- Typed amounts are read with the device's decimal mark
- Items sold in batches are bought by the batch
- An item bought and sold together is listed in order
- A character whose ledger this version can't read is held back from syncing, with a prompt to update, and never
  overwrites the newer copy
- Settings that can't be read are never saved over

## [1.1.0] - 2026-11-24

### Added
- Scan paper chronicle sheets with the document scanner
- Add portraits from Files, the clipboard and Demiplane

### Fixed
- Keep chronicle sheets when a character is renamed
- Keep track corrections when a character is renamed
- Recover settings iCloud rejected and give notes more room
- Build the Fame rosette from the artwork submodule

### Changed
- Pin the App Store tools to tabletop-kit 1.17.0
- Require tabletop-kit 1.17.0
- Specify scanning paper chronicle sheets
- Describe the new iCloud environment default
- Require tabletop-kit 1.16.0
- Update the Artwork submodule to 457740e
- Move BoonDownloads into its own file
- Add the shared App Store pipeline
- Require tabletop-kit 1.15.1
- Add the TestFlight targets
- Require tabletop-kit 1.14.0
- Add the App Store screenshot tour
- Require tabletop-kit 1.13.0

[1.1.0]: https://github.com/scooper4711/chronicle-keeper/releases/tag/v1.1.0

## [1.0.0] - 2026-11-21

### Added
- Initial release

[1.0.0]: https://github.com/scooper4711/chronicle-keeper/releases/tag/v1.0.0
