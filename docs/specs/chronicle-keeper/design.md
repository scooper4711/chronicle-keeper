# Chronicle Keeper design

SwiftPM package for macOS 14 and iOS 17: `ChronicleKeeperKit` (logic, no UI), `ChronicleKeeperUI` (SwiftUI),
`ChronicleKeeper` (the Mac executable); `ios/ChronicleKeeper.xcodeproj` hosts the iPhone and iPad app.
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
- `Progress/`: `ProgressCalculator` (track inference, XP, level), `CreditApplier` (the held-Chronicle queue,
  batch-flush and cap from R2.6-R2.8: sessions played below their adventure's own range are queued, in the order
  played, and applied as a batch once the character's level reaches it, each capped at that adventure's own
  highest level), `CharacterSettings` (the user's own data).
- `Roster/`: `CharacterRoster`, `CharacterMatcher`, and `EventDates` (R2.9), which the roster builds from every
  session and hands to each character's `ProgressCalculator`. The date a session counts as played on is
  `SessionProgress.date`, a `SessionDate` that says whether it was inferred; `PlayedSession.date` stays what
  paizo.com said, so nothing saved or synced passes a guess off as the site's.
- `Wealth/`: the ledger (R5). Amounts are `Int` copper pieces (`Money`; a credit is 10). `CharacterWealth` holds the
  starting funds override, the gold entered per session key and the purchases by ID; a `Purchase` places itself and its
  sale with `boughtAfter` and `soldAfter`, both session keys (empty for starting gold). `RewardTables` extends
  `CampaignRules` with starting funds and the placeholder amount; `WealthLedger` turns a `CharacterRecord` into lines
  with a running balance; `PurchaseLegality` marks level and rarity. Sources: the Guide's Character Creation, Purchasing
  Guidelines and Selling Gear sections, and its Treasure Bundles table ("10 TB" column); for Starfinder, the sfs2guide's
  Credits Awarded table. `Money.format` always gives gold pieces ("0.05 gp", "11.2 gp") or credits, as chronicles do;
  `parse` still takes "5 cp" or "2 sp". `Money.parse` follows the device's locale, as `format` does: its decimal mark
  ("11,5" is 11.5 gp in Norwegian) and its thousands separator, which counts only before exactly three digits; any other
  comma between digits is refused rather than guessed at, so a typo never multiplies an amount.
- Item prices: `make items` (`scripts/import-items.sh`) runs the `ItemPrices` tool (`ItemPriceImport` target) on the
  pf2e release pinned in `pf2e.release`. It reads both games' `equipment` packs (not `virtual-items` or
  `bestiary-items`; weapons, armor, shields, gear, consumables, backpacks and kits that have a coin or credit price)
  and writes `Resources/Items/items.json` and the ORC and OGL licenses, which git ignores. App and archive builds
  run it; a `CHANNEL=appstore` build fails without it. `ItemPriceList.bundled` loads it through `Bundle.module`.
- `Catalog/`: `AdventureCatalog`, `AdventureFinder`, and the search of the published adventures:
  `AdventureSearching`, `WarhornCatalog`, `WarhornScenario`, `CoverFinder`, `CoverTable` (see "Published adventures").
- `Storage/`, `Store/`: `CharacterRepository` keeps site data apart from the user's data, keyed by character number
  and a stable session key, so a refresh keeps edits. `CharacterStore` is the `@Observable` model;
  `AccountSession` is signed out, signed in or demo. `Demo/` holds the fictional account.
- `Sync/`: `SettingsMerge` (three-way, per field, overrides per session key), `SettingsSyncCore`, and the
  `CKSyncEngine` glue in `SettingsSync`. The container is `iCloud.io.github.scooper4711.ChronicleKeeper`.
  Boon and chronicle PDFs sync through iCloud Documents in the same container (`BoonLibrary`, `ChronicleLibrary`).
  Both stay off in a build without the entitlements; see "Turning iCloud on".

## Turning iCloud on

`CKContainer(identifier:)` stops the app when the entitlement is missing, and macOS stops an app at launch that
claims iCloud without a provisioning profile allowing it. So `SettingsSync` starts only when the Info.plist has
`ChronicleKeeperContainer`, and builds write that key only together with the entitlements. The PDFs need no key:
`FileManager.url(forUbiquityContainerIdentifier: nil)` is nil without the entitlements, and the libraries then use
the local folder.

- iPhone and iPad: `ios/ChronicleKeeper.entitlements` (CloudKit and CloudDocuments, the container as both iCloud
  and ubiquity container, `aps-environment`) and `ios/Info.plist`, which Xcode merges into the Info.plist it
  generates, for `ChronicleKeeperContainer`, the `remote-notification` background mode and
  `NSUbiquitousContainers`, which shows the PDFs in iCloud Drive and the Files app. Both name the container
  as `$(ICLOUD_CONTAINER)`, and the app target takes the two files from `APP_ENTITLEMENTS` and `APP_INFOPLIST`, all
  set in `ios/Signing.xcconfig`: a contributor's `Local.xcconfig` names their own team's container, or empties the
  two files for a team without iCloud. `make simulator` builds unsigned, so it leaves `ios/Info.plist` out.
- Mac: `Resources/ChronicleKeeper.entitlements` holds only the sandbox. `scripts/build-app.sh` calls
  `scripts/add-icloud-entitlements.sh` when it signs for the team and has a Developer ID provisioning profile with
  iCloud (`PROVISIONING_PROFILE`; the release workflow decodes it from the `DEVELOPER_ID_PROVISIONING_PROFILE`
  secret). That runs tabletop-kit's script of the same name for the CloudKit and push entitlements
  (`com.apple.developer.aps-environment` on the Mac), the two identifiers and the embedded profile, then adds
  CloudDocuments, the ubiquity container, `ChronicleKeeperContainer` and `NSUbiquitousContainers`. Without a
  profile, and in every ad hoc build, the app keeps its data on the Mac.

CloudKit keeps a Development and a Production database per container, and they don't see each other. Builds
installed from Xcode use Development; TestFlight and App Store builds use Production. The Mac build uses Production
unless `ICLOUD_ENVIRONMENT=Development`, which is how to sync it with a device installed from Xcode. Before a
release, deploy the schema to Production in the CloudKit Console.

## The ledger's storage

An older build decodes `CharacterSettings`, drops fields it doesn't know and writes the rest back, so the ledger
lives outside the `settings` JSON. In memory it is `CharacterSettings.wealth`, left out of its `CodingKeys`, so the
store, its updates and merging need nothing new. On disk `FileCharacterRepository` keeps it in `wealth.json`
beside `settings.json` and joins the two when loading. In CloudKit it is the `wealth` field (BYTES) of the
`Character` record: an old build sets only `settings` and `portrait`, so the server keeps `wealth`. The sync
ledger stores the agreed wealth beside the agreed settings (`SyncLedger.Entry.ancestorWealth`). `WealthMerge`
merges entered gold and purchases per key, three ways, as overrides are; the starting funds pick as a field.

The same risk lives inside the ledger: a later version may add fields to a purchase (Access, crafting). So
`CharacterWealth` and `Purchase` keep any field they don't know (`UnknownFields`) and write it back as it was,
and an older version moving or selling a purchase keeps what a newer one added.

Data this build can't read is never written over. When `settings.json` or `wealth.json` won't decode,
`CharacterStore` keeps nothing it read, says so, and refuses to save or merge settings until it can read them:
saving what little was read would overwrite both files, and syncing would spread the loss. A `Character` record on
the server whose ledger won't decode (saved by a newer version) is held back by `SettingsSync`: this device stops
sending that character, so its copy doesn't overwrite the newer one, and the user is told to update.

An item the item data sells in batches (candles, 1 cp for 10) is bought by the batch: the purchase is named
"Candle (10)" (`PricedItem.purchaseName`), its price is the batch's, and its quantity counts batches.

## App Store builds

TestFlight and the App Store get two builds under one bundle ID, uploaded from `main`:

- Mac: `make appstore` (`CHANNEL=appstore scripts/build-app.sh`) compiles the same sources with `-DAPP_STORE`, then
  hands the app to tabletop-kit's `scripts/package-appstore.sh` (its `appstore-build` spec), which compiles the icon,
  signs with the Apple Distribution identity and writes `build/appstore/Chronicle Keeper.pkg`.
  `PROVISIONING_PROFILE` is then the Mac App Store profile, which carries iCloud as the Developer ID one does.
  `TRIAL=1` checks the package without certificates; `UPLOAD=1` sends it to App Store Connect.
- iPhone and iPad: `make archive` (`scripts/archive-ios.sh`) writes `build/ChronicleKeeper.xcarchive`, which Xcode's
  Organizer uploads, signing it for distribution.

Both take the version from the newest `v` tag and the build number from the number of commits
(`scripts/version.sh`), so the two builds of one commit agree and every merge to `main` raises the number App Store
Connect needs to grow. `VERSION` and `BUILD_NUMBER` override them.

## Published adventures

"Who can play...?" (R3.7) lists the adventures the player's sessions name (`AdventureCatalog`) and adds the
published ones a search finds (`AdventureSearching`). `WarhornCatalog` is the search: it posts a GraphQL query to
`https://warhorn.net/graphql`, which needs no sign-in, for `globalScenarios(query:first:after:)`, whose `query`
matches any part of a scenario's name, a hundred to a page in the order of the names. The app keeps no copy.

Warhorn answers with every game's scenarios and with the entries events made for themselves, so
`WarhornScenario.adventure` keeps only those that are not `isCustom` and whose campaign code is PFS1, PFS2, SFS1
or SFS2, and drops the stand-ins ("Scenario Pending", "Infinite Scenario"). The search has no campaign filter, so:

- Text that starts with a number ("6-04", "7-1") is asked for under each campaign's code ("PFS2 6-04"), as
  Warhorn names a scenario "PFS2 6-04: An Enkindled Carnival". That is one small page per campaign.
- Other text is asked for as typed, from three characters on, and read for at most `longestSearch` pages; the
  adventures behind a common word come after pages of other games' scenarios. When pages are left unread the
  results say so (`isComplete`) and the finder asks for more of the title. Warhorn allows an address 300 requests
  in five minutes, which bounds this; a refusal (HTTP 429) is reported as such.

The finder waits 350 ms after the last keystroke, and a newer question cancels the search under way. Warhorn's
answer is kept with the question it answers, and merged into the list only while that is the question in the
field: until the new answer comes, the list holds just the player's own matches, never the last question's
published ones. An answer that comes in as its search is canceled is dropped. A failure leaves the player's own
adventures listed, with the reason (`AdventureSearchFailure`). The finder builds its `AdventureCatalog` when it
opens and again after a refresh or a new cover, and works the list out when the question, the answer or the
catalog changes, not on every redraw; each `AdventureEntry` works its name key out once.

`WarhornScenario.title` spells a name the way the Sessions tab does ("#6-04: An Enkindled Carnival", "Bounty #10:
Hillcross Roundup"), so `AdventureClassifier.code` reads the same code from both. Levels come from `minLevel` and
`maxLevel`, Repeatable from the campaign's tags, the cover from `coverArtUrl` (Paizo's own image servers), and
the kind from the title (`AdventureClassifier.kind(ofPublished:)`).

`AdventureEntry.isSameAdventure` decides both "already played" and which entries are one adventure: the same
product, or the same code in the same campaign, or, when either has no code, the same name. Warhorn numbers some
adventures the Sessions tab only names ("#7-01: Intro: Year of Battle's Spark" for "Intro to the Year of Battle's
Spark"), so `AdventureTitle.isSameName` compares the words that name the adventure, and takes one name inside a
longer one for the same when it is at least twelve letters long. `AdventureCatalog.merged` puts the published
entry in place of the sessions' spellings of it.

The demo's search is `DemoAdventureSearch`: a few made-up adventures, some of which its characters have played,
without the network.

### Covers of played adventures

`AccountSnapshot.covers` holds the cover of each adventure in the sessions, by `AdventureEntry.id`, in
`account.json` with the rest of what a refresh reads (R3.8). `CharacterStore.refresh` reads the account, carrying
the covers over, and then starts a cover pass (`CharacterStore.coverPass`), in which `CoverFinder.covers(of:)`
looks up each adventure that has none.

A numbered adventure is one search of the catalog by its number (`CoverFinder.searchText`: "6-04", "Bounty 14",
"Quest (Series 2) #14"), taking the cover of the result that `isSameAdventure`. Warhorn has a cover for every
numbered adventure it lists, so only one newer than its catalog comes back without.

Warhorn stores a cover's address as whoever entered it typed it, so `CoverHost.isAllowed` keeps only covers on
Paizo's servers (paizo.com and its subdomains, and the folder of Paizo's store on `cdn11.bigcommerce.com`) or
Warhorn's (`warhorn.imgix.net` and its S3 buckets), as PRIVACY.md promises. `WarhornScenario` drops any other
cover, `CoverTable` any other row, and the update script applies the same list. In November 2026 that left out
one cover, on imgur.

An adventure without a number is never asked for: paizo.com and Warhorn name these too differently to search
for one by the other ("Pathfinder Beginner Box: Menace Under Otari - Lower Dungeon" is Warhorn's "Menace Under
Otari, Part 2: Lower Level (from PF2 Beginner Box)"), and a title can carry the event the session was played at
("... - [PaizoCon 2024] PFS(2ed) ..."), which `AdventureTitle.withoutEvent` takes off before anything is compared
or sent. Its cover comes from `CoverTable`, which the app ships as `Resources/adventure-covers.json`: the some 460
adventures of the four campaigns that have no number on the Sessions tab (standalone adventures, Adventure Path
volumes, modules, one-shots, and each season's intro, which only Warhorn numbers), under Warhorn's names.
`CoverTable.cover(of:)` takes the entry whose name is most like the session's: the same name key, or else the
most letters of the entry's parts (the stretches between its punctuation, twelve letters or more) that the
session's name has, so that a volume of an Adventure Path gets its own cover and not the first volume's.
`scripts/update-adventure-covers.sh` (`make covers`) rewrites the table from Warhorn's catalog; it is run when
Paizo sanctions another such adventure, and for each season's intro. Warhorn's `globalScenarios` can't be listed
by campaign and returns the entries events make for themselves too (over 15,000), so the script searches for
each prefix Warhorn starts a name with instead, and the app doesn't list the catalog itself.

The pass is a task of its own: the refresh, and so signing in, doesn't wait for it. A first pass over some sixty
adventures takes about a quarter of a minute, later ones a request or two. One pass runs at a time, and an
adventure that is new while it runs waits for the next refresh. The covers are added to the account as it is
when the pass ends, which loading it again meanwhile may have replaced, and saved then. Signing out cancels the
pass, which then keeps nothing. A pass asks for at most `coversPerPass` adventures, to stay well inside the
requests Warhorn allows; the rest follow on later refreshes. A numbered adventure the catalog doesn't list is
asked for again on the next refresh; an error stops the pass quietly. `AccountSession.startCovers` gives the
user's own store its finder at launch, and waits for that first pass, which also covers an account saved by an
earlier version. Covers are not synced: like the account, each device looks them
up itself. `SessionHeader` and the finder's list of the player's own adventures read them from the store.

Paizo has worded an adventure's levels many ways ("1st- through 4th-level", "levels 1–4", "5th to 9th level
characters (Tiers: 5–6 and 8–9)", "for 5th-6th level characters"); `AdventureClassifier.levelRange` reads them all,
for every session.

## Interface

A `NavigationSplitView`: campaigns, then characters (portrait, level, XP bar), then a detail view (header,
reputation grid, adventures table with a track override menu, boons, settings). The table's title cell carries a
small gray caption, "Scenario · 4 XP (4 lost) · 2 Rep" (`SessionCaption`), instead of kind, XP and reputation columns.
Adventures, Gold/Credits & Purchases, Boons and Your Notes and Corrections each fold away under their title
(`CollapsibleSection`); whether each is folded is kept in the user defaults (`section.<id>.collapsed`), for every
character and across launches. The ledger's balance stays on the title line while it is folded. "Who Can Play..." is a sheet: a
search field, a campaign picker when the roster has more than one, a line saying what the list holds when that
isn't every match, and the adventures with their covers (`CoverArt`, an `AsyncImage`). A session's details show
the cover beside the title once it is known.

The detail column is a `NavigationStack`: an adventure's title in the table pushes `SessionDetailView` (R3.6),
which looks its session up in the store by ID on every update, so a changed track or a refresh shows there too. It
reads like a message: `SessionHeader` (the adventure as the subject, the Game Master as the sender, the date),
`SessionFacts` (each value the row abbreviates, with the sentence that explains it, from `SessionFactText` and
`SessionExplanation`, which the table's help tags share) and `ChronicleSheetSection`. That draws the sheet's first
pages full width (`ChroniclePageImages`, PDFKit thumbnails made off the main actor) and opens Quick Look on a tap;
its menu is the table's `ChronicleMenu` with a different label. `chronicleFiles` counts a sheet iCloud has not
brought to this device yet as attached (`hasFile` sees its placeholder), so before drawing, and before the menu's
Open, `waitUntilOnDevice` starts the download and checks every quarter second until `isOnDevice` (the file is
there and its `ubiquitousItemDownloadingStatus` isn't `.notDownloaded`). The section says it is downloading
meanwhile, and after `ICloudDownload.longest` (a minute) offers to try again. Boons work the same way:
`BoonFileButtons` shows a spinner while it brings a PDF down for Open or Print, and a crossed-out cloud if it
doesn't arrive. Both libraries get this, and `hasFile` and the coordinated write, from `ICloudDocumentLibrary`.
Share hands over the file as it is, since `ShareLink` gives nothing to wait in. The demo account attaches a
made-up sheet to its newest session (`DemoChronicles`), so the demo and the UI tests show one.

The ledger (`WealthSection`) sits between the adventures and the boons, for second edition campaigns only. Each group
has its name in bold across the columns (`GroupTitle`; "Before the First Adventure" for starting gear) and opens with a
`MoneyField` for the starting funds or what the adventure gave, labeled as the chronicle has it ("Gold earned", "Credits
earned"; the hint is only a placeholder), then its sales and purchases with the running balance. It reads like a
spreadsheet: column titles ("Treasure & Earned Income", or "Credits & Earned Income" in Starfinder; "Bought & Sold";
"Balance"), fixed-width number columns (`LedgerColumn`) so the amounts line up, stripes that alternate across the whole
ledger, and red for any negative amount (`MoneyText`). An item that may not be Society legal has an orange warning sign
(`LegalityWarning`) whose reasons show on hover and, for touch, in a popover when tapped. A purchase's menu edits,
sells, moves or removes it; a sale's menu moves or undoes it. Both lines are also `.draggable` onto any group's
`.dropDestination`; the menu is the way in for the keyboard, VoiceOver and the iPhone. `PurchaseEditor` takes the item,
its quantity (a short field with a stepper) and the price of one on one line, the price dropping below when the pane is
too narrow, and lists up to eight matches from `ItemPriceList` right under its field, as plain rows rather than a popover, so focus behaves on the
Mac and the iPad. A picked item's price stays editable; `PriceNote` shows the item data's price when it is overridden,
or says that an unmatched name is a custom item. A line falls to two rows (`ViewThatFits`) where one doesn't fit. The
demo gives Valeria and Zix-7 ledgers (`DemoWealth`) through the in-memory repository's starting settings.

A paper sheet is scanned with VisionKit's document scanner (`DocumentScanner`), which finds the sheet's edges,
straightens it, and has its own review screen to rotate, crop or rescan each page. Its pages are drawn upright
(`UIImage.uprightJPEG`) before `ChroniclePDF` makes them a PDF: Quartz draws a picture's pixels and ignores its
orientation tag, so a portrait photo would otherwise land sideways (as 1.0.0's camera did). Each JPEG goes into the
PDF as it is, on a page whose longer side is a letter sheet's 11 inches. The scanner is iOS only and isn't offered
where `VNDocumentCameraViewController.isSupported` is false, such as the Simulator.

## Artwork

Rexard art may be used inside the app only through the private `toolkit-artwork` submodule (`Artwork/`), never
committed here; builds without it fall back to SF Symbols. The icon is drawn in code.

`scripts/add-artwork.sh` writes the art, today the rosette beside Fame, into `ChronicleKeeperUI`'s resources as a
gitignored file, from `Artwork/rexard` or the full packs beside the checkout. The app and archive builds run it
first. With `REXARD_PACKS` named the art is required, which is how the release workflow builds: it fetches the
submodule with the `ARTWORK_SSH_KEY` secret, a read-only deploy key, and fails without the art. CI fetches it when
the secret is there, so pull requests from forks build with the symbol.
