# Chronicle Keeper requirements

Chronicle Keeper reads a player's My Organized Play pages on paizo.com and keeps a local record of every character:
adventures played, faction reputation, XP and level.

## 1. Signing in and reading the account

- **R1.1** The app signs in with the email address and password the user gives it. They are kept in the Keychain and
  go only to paizo.com.
- **R1.2** It reads the Summary tab (characters, campaign codes, faction reputation, Fame, Total Reputation) and
  the Sessions tab (every session, as player and as GM with credit applied to a character), following the page
  links until the range reaches the total.
- **R1.3** A GM-credit row is matched to a character by name and campaign. A row that matches no character is
  reported, never dropped.
- **R1.4** A crawl that ends early (a stale or missing next link, a total that doesn't add up) fails with an error
  that says what was being read, instead of returning a partial list.
- **R1.5** Unknown campaign codes and adventure titles stay readable and are shown as they are.
- **R1.6** A change on paizo.com is announced, never shown as a wrong password. Each failure has its own message:
  wrong password (with Paizo's own error text when it shows one), a refusal without a reason (names both causes),
  offline, paizo.com down, and a changed site (captcha, a sign-in that leads nowhere, pages that can't be read,
  broken paging, 404 or 410). A changed site says where to get an update.
- **R1.7** The Boons tab is read for each character's boons, and every boon PDF is downloaded once. A boon that
  can't be downloaded yet is shown as not available yet, not as an error. A boon that matches no character, or
  more than one, is reported.
- **R1.8** The user can attach their own chronicle sheet PDF to any session, or scan a paper one on the iPhone or
  iPad, replacing what was there before. Before a scan is saved, the user sees each page as it will be saved and
  can rotate, crop or rescan it; the PDF shows each page the way up the user left it. Chronicle PDFs are never fetched from paizo.com: they are the
  user's own files, kept and synced the same way as boon PDFs (R4.2).

## 2. Progress

- **R2.1** Each session's track is decided in this order: the user's override, the track its reputation implies
  (half the normal value for its kind is slow, the full value is normal), the character's default track. The
  result carries its source so the interface can show why.
- **R2.2** XP is the sum of each session's XP; level is the starting level plus XP divided by the campaign's XP per
  level, capped at the campaign's maximum level. Characters begin play at 0 XP.
- **R2.3** Starting level is chosen per character: 1st, 3rd, 5th or 7th in second edition, 1st in first edition.
- **R2.4** Faction reputation, Fame and Total Reputation are shown as Paizo reports them. Starfinder Society second
  edition shows no factions.
- **R2.5** Slow track in Starfinder Society (second edition) counts from 30 July 2026; earlier sessions are normal.
- **R2.6** A session played *below* its adventure's own level range is a held Chronicle: it doesn't bank its XP
  where it was played. Instead it is queued, in the order played, until the character's level reaches that
  range, then applied as a batch, in the order the held sessions were earned (Guide to Organized Play, "Applying
  Credit": "Normally, Chronicles are applied as soon as they are issued" — held ones are the exception). A
  session played within or above its range is never held: it applies immediately, in full, in play order.
- **R2.7** A held session, once applied, is capped so it can't carry the character's level past that specific
  adventure's own highest level: "a character's level cannot exceed the level of any Chronicle applied to them,
  [so] any out-of-level Chronicles applied are lost." The lost portion, if any, is shown. A held session the
  character never catches up to (nothing afterward reaches its range) is never applied at all.
- **R2.8** Each session shows the level the character was at walking in, when its credit lands (not the level it
  leaves them at), marked when that session was held (R2.6), and sorts by when its credit was actually banked
  (`applyOrder`), not necessarily by when it was played.
- **R2.9** paizo.com leaves the date off some sessions reported at a convention. Such a session counts as played on
  the last day of its event, as a convention's Chronicles apply when it ends: the latest date of the account's
  sessions with the same event code, any character's, when those dates fall within a week of each other. It sorts
  after the sessions really played that day, and the date is marked as worked out wherever it shows, with the
  reason. An event code in use for longer than a week (a store's or lodge's regular games) dates nothing, nor does
  an empty one, and such a session stays undated and counts as the oldest.
- **R2.10** Each faction's reputation shows the status the Guide gives it, under the faction's name: in Pathfinder
  Society (second edition) Ignored from 0, Liked from 20, Admired from 60 and Revered from 120; in Starfinder
  Society (first edition) Tier 0 to Tier 4, from 0, 5, 15, 25 and 45. Its explanation says how much reputation the
  next status still needs. Campaigns without such a ladder, and Fame and Total Reputation, show none.

## 3. Using the record

- **R3.1** Level and XP show in every overview.
- **R3.2** "Who can play...?" lists the characters in an adventure's campaign who haven't played it and whose level
  is in its range, with the rest shown dimmed and the reason. Repeatable adventures never count as played.
- **R3.3** Each character has notes, a portrait and a character sheet link.
- **R3.4** Boon PDFs can be opened, shared and printed.
- **R3.5** A demo account with fictional data runs without a Paizo account or the network.
- **R3.6** An adventure in a character's table opens that session's details, laid out like a message: the
  adventure, the Game Master, the character and the date at its head; then everything the row abbreviates spelled
  out (kind and levels, the level it was credited at, track, XP awarded and lost, progress into the level,
  reputation, points, event, paizo.com's notes), each with its explanation where the table has only a mark; then
  the session's chronicle sheet (R1.8), its pages shown in place, to open, share, remove or attach.

- **R3.7** "Who can play...?" offers every adventure Paizo has published for the Pathfinder and Starfinder Society
  campaigns the player has characters in (scenarios, specials, intros, quests, bounties, and the sanctioned
  adventures and Adventure Paths), not only the adventures in their own sessions. It searches Warhorn's catalog
  (warhorn.net) by code or title as the user types, so a new scenario shows as soon as Warhorn lists it, and can
  be narrowed to one campaign. Warhorn's other games and the entries events make for themselves are left out.
  Each adventure has its cover, its levels, and whether it is tagged Repeatable (R3.2). Before anything is
  typed, offline, and when Warhorn can't be reached, the adventures in the player's own sessions are listed, and
  the app says which it is showing. The demo searches a few made-up adventures of its own (R3.5).
- **R3.8** A session's details show its adventure's cover. The covers of the numbered adventures in the player's
  sessions are looked up in Warhorn's catalog once, by number, after the account is read, and saved with it, so
  showing one asks nobody; a later refresh looks up only the adventures that are new or had no cover. An
  adventure without a number (a standalone adventure, an Adventure Path volume, an intro) gets its cover from a
  table the app ships with, and is never asked for. A catalog that can't be reached leaves the account as it is,
  without a message. Warhorn is sent the text typed into "Who can play...?" and the numbers of the adventures in
  the sessions, and nothing that says whose they are: no title, and never the event a session was played at.

## 4. Data

- **R4.1** A refresh replaces the site's data and never touches the user's own data (overrides, default track,
  starting level, notes, links, portraits).
- **R4.2** The user's own data syncs between their devices through iCloud when the build has iCloud turned on, with
  edits on two devices both surviving. Site data doesn't sync.

## 5. Gold and purchases

The Guide asks that "all purchases must be recorded on a Chronicle Sheet or on a separate record tracker". Each
Pathfinder Society and Starfinder Society (second edition) character has such a ledger; first edition campaigns
have none.

- **R5.1** The ledger starts with the starting gold (or credits) for the character's starting level: 15, 75, 270 or
  720 gp in Pathfinder Society, 150, 750, 2,700 or 7,200 credits in Starfinder Society (the lump-sum option). The
  user can change it.
- **R5.2** Each adventure has one field for the gold or credits it gave, typed from the chronicle (Earn Income
  included). No formula feeds the balance: an empty field counts as nothing, and the ledger says how many
  adventures have none entered. As a placeholder only, the field shows the 10-Treasure-Bundle amount at the level
  the character played it at (Pathfinder) or the Credits Awarded at that level (Starfinder).
- **R5.3** A purchase records the item (from the item data, or typed by hand), its level, rarity, unit price and
  quantity, and the adventure it was bought after (or starting gold). Name, level, rarity and price are copied
  into the purchase, so it reads the same without the item data.
- **R5.4** A purchase can be sold, for half the price paid, after any adventure from the one it was bought after
  on. The sale is its own line under that adventure.
- **R5.5** A purchase or sale can be moved to after any other adventure. A purchase moved past its sale takes the
  sale along; a sale is never placed before its purchase.
- **R5.6** The balance runs oldest first, in the order credit was banked (R2.8): starting gold, then for each
  adventure its gold, its purchases and its sales. A negative balance is shown in red with a note; nothing is
  blocked.
- **R5.7** A purchase is marked, with the reason in words, when its item level is above the character's level at
  that point (minimum 2) or its rarity isn't common. Moving the purchase re-checks it.
- **R5.8** Purchases tied to a session paizo.com no longer lists are kept and shown in a last group, never dropped.
- **R5.9** The ledger is the user's own data (R4.1, R4.2): a refresh never touches it, and it syncs. A device on an
  older version that saves the character's other settings never erases it.

## 9. Conduct

- **R9.1** The app only reads the signed-in user's own account.
- **R9.4** Every request identifies the app and its author: Safari's user agent followed by
  `ChronicleKeeper/<version> (+https://github.com/scooper4711/chronicle-keeper)`, so Paizo can tell the traffic
  apart and block it if it has to. No email address goes in the header.
- **R9.5** The repository holds no real account data; fixtures are sanitized.
