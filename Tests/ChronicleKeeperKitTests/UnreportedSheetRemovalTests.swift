import Foundation
import Testing
@testable import ChronicleKeeperKit

/// What the user does with a chronicle sheet whose session doesn't arrive as expected (R1.14, R1.15): deleting
/// it, attaching it to another adventure and moving it to another character; and the name its adventure gets.
@MainActor
struct UnreportedSheetRemovalTests: UnreportedStoreTesting {
    // MARK: - Removing

    @Test func deletingASheetRemovesEverythingItGaveAndLeavesItsPurchases() async throws {
        let library = library()
        let store = await store(AccountBox(), library: library)
        add(UnreportedFactory.reading(), to: store)
        let unreported = try sheet(in: store)
        store.update(valeria) { settings in
            settings.setOverride(SessionOverride(track: .slow), for: unreported)
            settings.wealth.add(Purchase(id: "rope", name: "Rope", unitPrice: 50, boughtAfter: key))
        }
        #expect(try record(valeria, in: store).settings.wealth.purchaseCount(after: key) == 1)
        store.deleteUnreportedSheet(unreported, characterNumber: valeria)
        let record = try record(valeria, in: store)
        #expect(record.sessions.count == 1)
        #expect(record.settings.wealth.sheetReadings.isEmpty)
        #expect(record.settings.wealth.earned.isEmpty)
        #expect(record.settings.overrides.isEmpty)
        #expect(store.chronicleFiles.isEmpty)
        #expect(!library.hasFile(at: library.pendingURL("123456-2001/a")))
        let last = try #require(WealthLedger(record: record).groups.last)
        #expect(last.place == .unlisted)
        #expect(last.lines.count == 1)
    }

    @Test func aReportedSessionsSheetIsNotDeletedThatWay() async throws {
        let store = await store(AccountBox())
        let listed = SessionFactory.session()
        store.keep(UnreportedFactory.reading(code: "6-04"), for: listed, characterNumber: valeria)
        store.deleteUnreportedSheet(listed, characterNumber: valeria)
        #expect(store.sheetReading(for: listed, characterNumber: valeria) != nil)
    }

    /// Instead of deleting it, the user attaches the sheet to an adventure paizo.com lists: only the character's
    /// reported adventures without a sheet are offered.
    @Test func aSheetCanBeAttachedToAReportedAdventureWithoutOne() async throws {
        let account = AccountBox()
        account.report([reported])
        let library = library()
        let store = await store(account, library: library)
        store.keep(UnreportedFactory.reading(code: "6-04"), for: SessionFactory.session(), characterNumber: valeria)
        add(UnreportedFactory.reading(code: "6-50"), to: store)
        let unreported = try sheet(in: store)
        store.update(valeria) { $0.wealth.add(Purchase(id: "rope", name: "Rope", unitPrice: 50, boughtAfter: key)) }
        let offered = store.sessionsWithoutSheet(of: try record(valeria, in: store))
        #expect(offered.map(\.session) == [reported])

        store.attach(PendingSheetMatcher.Match(sheet: unreported, from: valeria, session: reported, to: valeria))
        let record = try record(valeria, in: store)
        #expect(record.unreportedCount == 0)
        #expect(record.settings.wealth.sheetReadings["777#2"]?.code == "6-50")
        #expect(record.settings.wealth.purchases["rope"]?.boughtAfter == "777#2")
        #expect(store.chronicleFiles[reported.id] == library.fileURL(characterNumber: valeria, session: reported))
        #expect(store.sessionsWithoutSheet(of: record).isEmpty)
    }

    // MARK: - Reported for another character

    @Test func aSheetReportedForAnotherCharacterMovesOnlyWhenTheUserSaysSo() async throws {
        let account = AccountBox()
        let library = library()
        let store = await store(account, library: library)
        add(UnreportedFactory.reading(eventCode: "9999"), to: store)
        store.update(valeria) { $0.wealth.add(Purchase(id: "rope", name: "Rope", unitPrice: 50, boughtAfter: key)) }
        let pips = UnreportedFactory.pipsSession("#6-05: Ashes Over Highhelm", eventCode: "9999")
        account.report([pips])
        await store.refresh()

        let unreported = try sheet(in: store)
        let match = try #require(store.sessionElsewhere(for: unreported, of: try record(valeria, in: store)))
        #expect(try record(valeria, in: store).unreportedCount == 1)
        #expect(match.to == pip)

        store.attach(match)
        let mine = try record(valeria, in: store)
        let theirs = try record(pip, in: store)
        #expect(mine.unreportedCount == 0)
        #expect(mine.settings.wealth.sheetReadings.isEmpty)
        #expect(mine.settings.wealth.earned.isEmpty)
        // Her purchase was made with her gold: it stays in her ledger, in its last group.
        #expect(mine.settings.wealth.purchases["rope"]?.boughtAfter == key)
        #expect(theirs.settings.wealth.sheetReadings["9999#2"]?.xp == 4)
        #expect(theirs.settings.wealth.earned == ["9999#2": 1_400])
        #expect(store.chronicleFiles == [pips.id: library.fileURL(characterNumber: pip, session: pips)])
    }

    @Test func keepingWaitingClearsTheOfferToMoveASheet() async throws {
        let account = AccountBox()
        let store = await store(account)
        add(UnreportedFactory.reading(eventCode: "9999"), to: store)
        account.report([UnreportedFactory.pipsSession("#6-05: Ashes Over Highhelm", eventCode: "9999")])
        await store.refresh()
        let unreported = try sheet(in: store)
        let match = try #require(store.sessionElsewhere(for: unreported, of: try record(valeria, in: store)))
        store.clearWarning(match.id, for: unreported, characterNumber: valeria)
        #expect(store.sessionElsewhere(for: unreported, of: try record(valeria, in: store)) == nil)
        #expect(try record(valeria, in: store).unreportedCount == 1)
        #expect(store.sessionElsewhere(for: SessionFactory.session(), of: try record(valeria, in: store)) == nil)
    }

    // MARK: - The adventure's name

    private var ashes: PublishedAdventure {
        var adventure = Covers.published("#6-05: Ashes Over Highhelm", cover: Covers.enough)
        adventure.levelRange = LevelRange(lowest: 1, highest: 4)
        return adventure
    }

    @Test func theCatalogGivesTheAdventuresNameLevelsAndCover() async throws {
        let store = await store(AccountBox())
        let search = StubSearch([ashes])
        await store.useCoverFinder(CoverFinder(search: search))
        add(UnreportedFactory.reading(), to: store)
        await store.waitForNames()
        let named = try sheet(in: store)
        #expect(search.questions.contains("6-05"))
        #expect(named.adventure.titleWithLevels == "#6-05: Ashes Over Highhelm (1–4)")
        #expect(store.cover(of: named) == Covers.enough)
        #expect(store.settings(for: valeria).wealth.sheetReadings[key]?.title == "#6-05: Ashes Over Highhelm")
    }

    @Test func aSheetGivenAnotherNumberLosesTheNameLookedUpForTheFirst() async throws {
        let store = await store(AccountBox())
        await store.useCoverFinder(CoverFinder(search: StubSearch([ashes])))
        add(UnreportedFactory.reading(), to: store)
        await store.waitForNames()
        store.keep(UnreportedFactory.reading(code: "6-06"), for: try sheet(in: store), characterNumber: valeria)
        await store.waitForNames()
        #expect(try sheet(in: store).adventure.title == "#6-06")
        store.keep(UnreportedFactory.reading(code: "6-06") { $0.xp = 2 }, for: try sheet(in: store),
                   characterNumber: valeria)
        #expect(try sheet(in: store).adventure.title == "#6-06")
    }

    @Test func aCatalogThatCantBeReachedLeavesTheNumber() async throws {
        struct Offline: Error {}
        let store = await store(AccountBox())
        await store.useCoverFinder(CoverFinder(search: StubSearch(failure: Offline())))
        add(UnreportedFactory.reading(), to: store)
        await store.waitForNames()
        #expect(try sheet(in: store).adventure.title == "#6-05")
    }

    @Test func signingOutStopsTheLookup() async throws {
        let store = await store(AccountBox())
        let held = HeldSearch()
        let waiting = Task { await store.useCoverFinder(CoverFinder(search: held)) }
        add(UnreportedFactory.reading(), to: store)
        store.signOut()
        held.release()
        await waiting.value
        await store.waitForNames()
        #expect(store.settings(for: valeria).wealth.sheetReadings[key]?.title == nil)
    }
}
