# Character Keeper design

SwiftPM package for macOS 14 and iOS 17: `CharacterKeeperKit` (logic, no UI), `CharacterKeeperUI` (SwiftUI),
`CharacterKeeper` (the Mac executable); `ios/CharacterKeeper.xcodeproj` hosts the iPhone and iPad app.
Dependencies: SwiftSoup, and tabletop-kit's `AppNotices` for About.

## The site

paizo.com is an old WebObjects site.

- **Sign-in** posts the form (hidden fields, email `e`, password `zzz`) to its session-bound action as an Ajax
  submit (`/wo/` becomes `/ajax/`, with `?_u=SignInPageAjaxSignIn&<ms>`). A wrong password answers HTTP 200 with the
  form again and an `alert-message` box.
- **Summary tab**: two table rows per character. Used for the character list, campaign codes and Paizo's totals.
- **Sessions tab**: 13-cell rows `Date | GM | Scenario | Points | EventCode | EventName | Session# | Player# |
  Character | Faction | Rep | Notes | Edit`, 50 per page, newest first; the "next >" link is session-bound and is
  taken from the page just loaded. Player rows carry the character number; GM-credit rows carry only the player
  number. The natural key is event code + session number + character.
- **Boons tab**: a plain table after "Boons you have purchased:"; each row has a `downloadBoonPDF` link taking
  opaque character and reward IDs. A response that doesn't start with `%PDF` means not available yet.

## Kit

- `Networking/`: `HTTPClient` and `URLSessionHTTPClient` (the only `URLSession`; sets the user agent, R9.4),
  `OrganizedPlayClient` (actor: sign-in, paging with a total check, PDFs), `KeychainCredentialStore`,
  `FailureMessage` and `SignInReply` (R1.6).
- `Parsing/`: parsers for the sign-in page, Summary, Sessions (`SessionRowParser`, `PointsParser`), Boons;
  `AdventureClassifier` (kind, level range, code).
- `Rules/CampaignRules`: XP and reputation per kind and edition, XP per level (second edition 12, first edition 3),
  starting levels, factions, the SFS2 slow-track date. Values come from the Guide to Organized Play on
  lorespire.paizo.com and are noted next to the code.
- `Progress/`: `ProgressCalculator` (track inference, XP, level), `CharacterSettings` (the user's own data).
- `Roster/`: `CharacterRoster`, `CharacterMatcher`. `Catalog/`: `AdventureCatalog`, `AdventureFinder`.
- `Storage/`, `Store/`: `CharacterRepository` keeps site data apart from the user's data, keyed by character number
  and a stable session key, so a refresh keeps edits. `CharacterStore` is the `@Observable` model;
  `AccountSession` is signed out, signed in or demo. `Demo/` holds the fictional account.
- `Sync/`: `SettingsMerge` (three-way, per field, overrides per session key), `SettingsSyncCore`, and the
  `CKSyncEngine` glue in `SettingsSync`. The container is `iCloud.io.github.scooper4711.CharacterKeeper`.
  Boon PDFs sync through iCloud Drive. Both stay off in a build that doesn't name the container (ad hoc builds).

## Interface

A `NavigationSplitView`: campaigns, then characters (portrait, level, XP bar), then a detail view (header,
reputation grid, adventures table with a track override menu, boons, settings). "Who Can Play..." is a sheet.

## Artwork

Rexard art may be used inside the app only through the private `toolkit-artwork` submodule, never committed here;
builds without it fall back to SF Symbols. The icon is drawn in code.
