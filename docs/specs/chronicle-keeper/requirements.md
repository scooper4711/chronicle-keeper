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
  can rotate, crop or rescan it, and then confirms the page and what was read from it on one screen (R1.11); the
  PDF shows each page the way up the user left it. Chronicle PDFs are never fetched from paizo.com: they are the
  user's own files, kept and synced the same way as boon PDFs (R4.2).
- **R1.9** The Boons tab's free reward lists are read too: Chronicle Boons and Game Rewards, for Pathfinder Society
  (second edition) and Starfinder Society (first edition). They are the same for every player and change rarely, so
  they are read once and then again only when the copy is older than 30 days, after a refresh and without holding it
  up. Opening a list is a request to read it, with no character chosen: nothing is bought, and R9.1 holds. A list
  that can't be read leaves the saved copy and shows no message.
- **R1.10** The app reads a chronicle sheet when it is attached or scanned: the adventure's number, the character
  number (the Organized Play number and the character's own part), the XP gained, the gold or credits gained and
  the event code. Reading happens on the device and nothing is sent anywhere. A sheet a program filled in is read
  from the PDF's own text; a scanned one by text recognition, handwriting included.
  - It never guesses. A value is read only when its label is on the sheet once, the sheet's format says where the
    label's box is, exactly one thing is written in that box, and that is a clean number. Anything less leaves the
    value unread.
  - An unread value changes nothing: XP, track and the ledger's gold are then exactly as without a sheet.
  - Paizo moved the reward boxes' labels over the years (under the box, over it, then under again), so the reader
    takes the format from the sheet's own labels. It is tested against every Pathfinder Society and Starfinder
    Society (second edition) chronicle. First edition sheets are best effort.
- **R1.11** One screen confirms the picture and what was read, with one button. It shows the page, which the user
  can zoom and rotate left or right, with the places the values were read from outlined, and editable fields for
  the character number, the XP and the gold or credits, filled with what was read. Text recognition misreads
  handwriting with full confidence, so nothing read is used before the user has seen it there. A value that
  disagrees with paizo.com's record or the ledger says so beside its field, so a misread is corrected before it
  becomes a warning (R1.12). A PDF goes through the same screen. A sheet attached before this version can be read
  later, from its menu, and one that was read can be checked and corrected again.
- **R1.12** A sheet and paizo.com's record can disagree: GMs make mistakes reporting and filling in sheets. The app
  then warns, in words, and the user can clear each warning once satisfied; nothing is blocked.
  - The sheet names another character than the session was reported for. Characters are compared by number, never
    by name, and by the character's own part of the number: every character of a player shares the Organized Play
    part.
  - The sheet is for another adventure than the session it is attached to.
  - The sheet's XP isn't what paizo.com's record gives (R2.11), or isn't XP the adventure can give.
  - The sheet's gold isn't what the user typed in the ledger (R5.11).
  - A cleared warning comes back when the sheet is read again with another value.
- **R1.13** On the Mac, and on an iPad with Files beside the app, a PDF dropped on a session's row or on its
  Chronicle Sheet section is attached to that session, through the same confirmation. One file at a time; a
  session that has a sheet asks before replacing it.
- **R1.14** A player gets the chronicle sheet at the table, often days before the GM reports the session. "Add
  Chronicle…" on a character takes a sheet whose session paizo.com doesn't list yet: scanned or attached, and
  confirmed on the same screen (R1.11), which then also asks for the scenario number and the day played. The sheet
  can't be kept without a scenario number, as that is what its session is found by (R1.15).
  - The sheet shows as a row of its own among the adventures and counts right away: its XP toward the level
    (what was read or typed; otherwise the normal XP for its kind of adventure), its gold in the ledger, and
    purchases can be placed after it. It counts as played in "Who can play...?" (R3.2), and is held or capped like
    any session (R2.6, R2.7).
  - It doesn't count for rewards to claim (R3.9): paizo.com hands none out for a session it doesn't have.
    Reputation and Fame stay as paizo.com reports them.
  - An unreported row never passes for a reported one. Its title is in another color; "Not reported yet" and the
    day it was added stand where "GM credit" goes; it has an "Unreported" badge, which says the same to VoiceOver
    and on a hover; the section's title counts such rows ("Adventures (12 · 2 not reported)"). The totals that
    include one say so: under the level in the character's header, as a badge beside the character in the
    sidebar, and in the ledger group's title. Its details say at the top that its XP and gold come from the
    chronicle sheet, and leave out what only paizo.com knows (Game Master, reputation, points, event).
  - The adventure is named by its number until its name is known: from another character's session of the same
    adventure, or looked up in the catalog (R3.8), which also gives its levels and cover.
  - The user can remove such a sheet at any time: some sessions are never reported, and a sheet can be added
    twice or to the wrong character. The app then asks whether to delete the chronicle or to attach it to another
    adventure, and offers for that only the character's reported adventures that have no chronicle sheet.
    Deleting removes the row, the PDF, what was read and its gold; purchases made after it stay, in the ledger's
    last group (R5.8), which the app says first. Attaching keeps everything, as in R1.15.
- **R1.15** When paizo.com lists the session, the sheet becomes that session's.
  - A character plays an adventure once for credit. So a sheet and a session of the same character with the same
    scenario number are the same session, whatever their dates, and a sheet never goes to a session with another
    scenario number. This holds when a refresh brings the session and when a sheet is added for an adventure
    paizo.com already lists. Four sheets from one convention day land on the right sessions whatever order the
    GMs report in. A session that has a chronicle sheet keeps it: a second sheet for it stays unreported, with a
    warning that paizo.com already lists the adventure.
  - The row then is the reported session, and everything the user kept for the sheet is the session's: what was
    read, its gold, the correction to its track or XP, the purchases bought and sold after it, and the links from
    purchases to it (R5.10), on every character. Gold the user typed for the reported session and a correction
    they made to it stay, and the sheet's warnings (R1.12) compare with them.
  - This is done at once, on whichever device reads the account first, and syncs (R4.2). The PDF follows on a
    device that has it: one that iCloud hasn't brought down yet still shows as the session's sheet and is moved
    when it has come. Nothing counts twice meanwhile.
  - A sheet with no session under its own character, whose scenario number and event code are those of a session
    of another of the user's characters in the same campaign, is not moved on its own. The app says so and offers
    to move the sheet to that character or to keep waiting for a corrected report. Moved, the sheet, what was
    read, its gold and its correction go to that character's session; the purchases made after it are the first
    character's own and stay in that ledger's last group.

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
- **R2.11** A chronicle sheet's XP (R1.10) counts for its session, ahead of what paizo.com's record implies and
  behind the user's own override, wherever it is XP the adventure can give: its normal XP, or half of that where
  slow track is allowed. Half means slow track, the full amount normal. XP the adventure can't give isn't counted
  and is reported (R1.12). The session says that its track and XP come from the Chronicle Sheet.

## 3. Using the record

- **R3.1** Level and XP show in every overview.
- **R3.2** "Who can play...?" lists the characters in an adventure's campaign who haven't played it and whose level
  is in its range, with the rest shown dimmed and the reason. Repeatable adventures never count as played. A
  chronicle sheet added ahead of its report counts as played (R1.14).
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
  the sessions and in the chronicle sheets added ahead of their report (R1.14), and nothing that says whose they
  are: no title, and never the event a session was played at.
- **R3.9** The app signals each free reward a character may claim on paizo.com and hasn't yet.
  - A Chronicle Boon is one when the character has a session of the adventure it names (as player or as Game
    Master with credit), by its number or else by its title. A Game Reward is one when the character has the
    reputation it asks for (a status such as Liked, R2.10, or a number) with the named faction or with any faction,
    has played the number of sessions it asks for, or has played the adventures it names (one of them for "OR",
    each of them for "AND").
  - A reward the character already has, by the name the Boons tab lists, is never signaled. Nor is one for a
    session paizo.com doesn't list yet (R1.14).
  - An adventure's "Boon A", "Boon B" and "Boon C" are alternatives: the Chronicle Sheet says which one was earned.
    A character who has one of them isn't eligible for the others, so nothing is signaled; a character who has
    none gets one signal that names the choices.
  - A condition the app can't check from the account (every part of a series, a compilation, a Chronicle Sheet
    count) is never signaled, nor is a reward for a character whose name another character shares, as the Boons
    tab names only the character. A missed reward is better than a false one.
  - Known limit: each character is checked on its own. A boon worded for the whole account ("One of your
    characters…", "Your characters…") is signaled for every character with a session of its adventure until that
    character has it, even after another character claimed it.
  - The signal is a sparkle, moving unless the device reduces motion: beside the adventure in the character's
    table and in the session's details, on the faction's tile, on the Boons section's title and beside the
    character in the sidebar. It says which reward and why, and opens a list with a button to the Boons tab on
    paizo.com, where the user claims it. "Ready to Claim" at the top of the Boons section lists them all. After
    the next refresh a claimed reward is among the character's boons and its signal is gone.

## 4. Data

- **R4.1** A refresh replaces the site's data and never touches the user's own data (overrides, default track,
  starting level, notes, links, portraits), with one exception: what the user kept for a chronicle sheet added
  ahead of its report is filed under the session when a refresh brings it (R1.15). Nothing of it is changed or
  lost.
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
  included) or filled from it (R5.11). No formula feeds the balance: an empty field counts as nothing, and the
  ledger says how many adventures have none entered. As a placeholder only, the field shows the
  10-Treasure-Bundle amount at the level the character played it at (Pathfinder) or the Credits Awarded at that
  level (Starfinder).
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
  that point (minimum 2) or its rarity isn't common. Moving the purchase re-checks it. Linking it clears the
  marks (R5.10).
- **R5.8** Purchases tied to a session paizo.com no longer lists, or to a chronicle sheet the user deleted (R1.14),
  are kept and shown in a last group, never dropped.
- **R5.9** The ledger is the user's own data (R4.1, R4.2): a refresh never touches it, and it syncs. A device on an
  older version that saves the character's other settings never erases it.
- **R5.10** The user can link a marked purchase to what makes it legal: a boon, or a Chronicle Sheet (a session).
  - The app doesn't check that the boon or the Chronicle Sheet grants the item: the user vouches for it. Either
    kind of link clears every mark, the level one too.
  - A linked purchase shows a green check in place of the warning, and its name in the normal color. The check
    says what the link waives, which boon or Chronicle Sheet it is and whose: "Uncommon: Access from Korbul
    Thornbrook's boon Abendego's Cannon." Unlinking brings the marks back.
  - The boons and Chronicle Sheets offered are those of the characters in the same campaign (the same game and
    edition), the buyer's own first. A boon may belong to another character: one worded "One of your characters
    gains access…" is claimed by one character and used by another. A boon whose character the app can't tell
    (R3.9) isn't offered.
  - A boon is linked to at most one purchase, across all characters. Choosing one that is linked already moves
    the link, after saying what it is linked to now. A Chronicle Sheet usually lists several items, so it may be
    linked to any number of purchases.
  - Selling the purchase doesn't free the boon: the link stays with the purchase. Removing the purchase does.
  - The Boons section shows the purchase a boon is used for, and whose.
  - The link is part of the ledger (R5.9). Two devices can each link one boon before they sync: both purchases
    then keep their link, and both say that the boon is linked twice, for the user to settle.
- **R5.11** A chronicle sheet's gold or credits (R1.10) fill the adventure's field in the ledger when that field
  is empty, and never replace what the user typed. An amount the sheet filled in is marked as the sheet's, and
  follows the sheet when its reading is corrected. Where the sheet and a typed amount differ the app says so
  (R1.12) and offers to take the sheet's amount. Only the first sheet format has an Earn Income box, which is added
  to the gold; on later sheets the GM may have left Earn Income out, which is for the user to see in the
  confirmation (R1.11).

## 9. Conduct

- **R9.1** The app only reads the signed-in user's own account.
- **R9.4** Every request identifies the app and its author: Safari's user agent followed by
  `ChronicleKeeper/<version> (+https://github.com/scooper4711/chronicle-keeper)`, so Paizo can tell the traffic
  apart and block it if it has to. No email address goes in the header.
- **R9.5** The repository holds no real account data; fixtures are sanitized.
- **R9.6** Every source book the bundled item data comes from is named in exactly one of the notices the app
  ships: the ORC License's attribution notice or the Open Game License's Section 15. An import that meets a
  source it can't attribute fails, so no item ships without its book's notice.
