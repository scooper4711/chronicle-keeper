# Character Keeper requirements

Character Keeper reads a player's My Organized Play pages on paizo.com and keeps a local record of every character:
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
- **R2.8** Each session shows the level the character reaches once its own credit lands (not the level they were
  at beforehand), marked when that session was held (R2.6), and sorts by when its credit was actually banked
  (`applyOrder`), not necessarily by when it was played.

## 3. Using the record

- **R3.1** Level and XP show in every overview.
- **R3.2** "Who can play...?" lists the characters in an adventure's campaign who haven't played it and whose level
  is in its range, with the rest shown dimmed and the reason. Repeatable adventures never count as played.
- **R3.3** Each character has notes, a portrait and a character sheet link.
- **R3.4** Boon PDFs can be opened, shared and printed.
- **R3.5** A demo account with fictional data runs without a Paizo account or the network.

## 4. Data

- **R4.1** A refresh replaces the site's data and never touches the user's own data (overrides, default track,
  starting level, notes, links, portraits).
- **R4.2** The user's own data syncs between their devices through iCloud when the build has iCloud turned on, with
  edits on two devices both surviving. Site data doesn't sync.

## 9. Conduct

- **R9.1** The app only reads the signed-in user's own account.
- **R9.4** Every request identifies the app and its author: Safari's user agent followed by
  `CharacterKeeper/<version> (+https://github.com/scooper4711/character-keeper)`, so Paizo can tell the traffic
  apart and block it if it has to. No email address goes in the header.
- **R9.5** The repository holds no real account data; fixtures are sanitized.
