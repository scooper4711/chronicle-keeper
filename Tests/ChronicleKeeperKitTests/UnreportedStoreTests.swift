import Foundation
import Testing
@testable import ChronicleKeeperKit

/// Adding a chronicle sheet ahead of its report, and what happens to it when paizo.com lists the session, when
/// the user removes it and when the session turns up for another character (R1.14, R1.15).
@MainActor
struct UnreportedStoreTests: UnreportedStoreTesting {
    // MARK: - Adding

    @Test func aSheetKeptAheadOfItsReportIsASessionWithItsGoldAndItsPDF() async throws {
        let library = library()
        let store = await store(AccountBox(), library: library)
        add(UnreportedFactory.reading { $0.playedOn = nil; $0.addedAt = nil }, to: store)
        let record = try record(valeria, in: store)
        let reading = try #require(record.settings.wealth.sheetReadings[key])
        #expect(record.unreportedCount == 1)
        #expect(record.level.xp == 8)
        #expect(record.settings.wealth.earned[key] == 1_400)
        #expect(reading.addedAt != nil)
        #expect(reading.playedOn == SheetDay.text(of: Date()))
        let file = library.folder.appendingPathComponent("Pending/123456-2001/a.pdf")
        #expect(store.chronicleFiles[key] == file)
        #expect(try Data(contentsOf: file) == pdf)
        #expect(store.hasSheet(try sheet(in: store), characterNumber: valeria))
    }

    @Test func checkingTheSheetAgainKeepsWhenItWasAddedAndTheDayPlayed() async throws {
        let store = await store(AccountBox())
        add(UnreportedFactory.reading(), to: store)
        let first = try #require(store.settings(for: valeria).wealth.sheetReadings[key])
        let again = UnreportedFactory.reading { $0.xp = 2; $0.playedOn = nil; $0.addedAt = nil }
        store.keep(again, for: try sheet(in: store), characterNumber: valeria)
        let second = try #require(store.settings(for: valeria).wealth.sheetReadings[key])
        #expect(second.xp == 2)
        #expect(second.addedAt == first.addedAt)
        #expect(second.playedOn == "2026-06-01")
    }

    // MARK: - The report arrives

    /// A sheet with a correction, a purchase bought and sold after it and another character's purchase linked to
    /// it, whose session the GM then reports.
    private func storeAfterTheReport(library: ChronicleLibrary) async throws -> CharacterStore {
        let account = AccountBox()
        let store = await store(account, library: library)
        add(UnreportedFactory.reading(), to: store)
        let unreported = try sheet(in: store)
        store.update(valeria) { settings in
            settings.setOverride(SessionOverride(track: .slow), for: unreported)
            var rope = Purchase(id: "rope", name: "Rope", unitPrice: 50, boughtAfter: key)
            rope.soldAfter = key
            settings.wealth.add(rope)
        }
        store.update(pip) { settings in
            var wand = Purchase(id: "wand", name: "Wand", unitPrice: 300)
            wand.accessLink = AccessLink(session: unreported, of: store.roster.characters[0])
            settings.wealth.add(wand)
        }
        account.report([reported])
        await store.refresh()
        return store
    }

    /// The row becomes the reported session and keeps its gold, correction and purchases.
    @Test func aRefreshThatBringsTheSessionFilesEverythingUnderIt() async throws {
        let store = try await storeAfterTheReport(library: library())
        let record = try record(valeria, in: store)
        let wealth = record.settings.wealth
        #expect(record.unreportedCount == 0)
        #expect(record.sessions.count == 2)
        #expect(record.level.xp == 6)
        #expect(wealth.sheetReadings[key] == nil)
        #expect(wealth.sheetReadings["777#2"]?.xp == 4)
        #expect(wealth.sheetReadings["777#2"]?.playedOn == nil)
        #expect(wealth.earned == ["777#2": 1_400])
        #expect(wealth.purchases["rope"]?.boughtAfter == "777#2")
        #expect(wealth.purchases["rope"]?.soldAfter == "777#2")
        #expect(record.settings.override(for: reported)?.track == .slow)
        #expect(record.settings.overrides[key] == nil)
        #expect(store.sheetWarnings(for: reported, record: record).isEmpty)
    }

    @Test func theSheetsPDFAndTheLinksToItFollowItToTheSession() async throws {
        let library = library()
        let store = try await storeAfterTheReport(library: library)
        let link = try #require(store.settings(for: pip).wealth.purchases["wand"]?.accessLink)
        #expect(link.sourceID == "123456-2001/777#2")
        #expect(link.sourceName == "#6-05: Ashes Over Highhelm")
        let place = library.fileURL(characterNumber: valeria, session: reported)
        #expect(store.chronicleFiles == [reported.id: place])
        #expect(try Data(contentsOf: place) == pdf)
        #expect(!library.hasFile(at: library.pendingURL("123456-2001/a")))
    }

    /// Gold the user typed for the reported session, and a correction made to it, are the session's own.
    @Test func whatTheReportedSessionAlreadyHasStays() async throws {
        let store = await store(AccountBox())
        let listed = SessionFactory.session()
        let wrongNumber = try addSheetNamed("6-99", to: store)
        store.update(valeria) { settings in
            settings.wealth.earned["1234#1"] = 2_000
            settings.setOverride(SessionOverride(xp: 3), for: listed)
            settings.setOverride(SessionOverride(track: .slow), for: wrongNumber)
        }
        store.attach(PendingSheetMatcher.Match(sheet: wrongNumber, from: valeria, session: listed, to: valeria))
        let record = try record(valeria, in: store)
        #expect(record.settings.wealth.earned == ["1234#1": 2_000])
        #expect(record.settings.override(for: listed) == SessionOverride(xp: 3))
        #expect(Set(store.sheetWarnings(for: listed, record: record).map(\.kind)) == [.adventure, .funds])
    }

    private func addSheetNamed(_ code: String, to store: CharacterStore) throws -> PlayedSession {
        add(UnreportedFactory.reading(code: code), to: store)
        return try sheet(in: store)
    }

    @Test func aSheetKeptForAnAdventurePaizoAlreadyListsGoesToThatSessionAtOnce() async throws {
        let library = library()
        let store = await store(AccountBox(), library: library)
        add(UnreportedFactory.reading(code: "6-04"), to: store)
        let record = try record(valeria, in: store)
        let listed = SessionFactory.session()
        #expect(record.unreportedCount == 0)
        #expect(record.settings.wealth.sheetReadings["1234#1"]?.funds == 1_400)
        #expect(store.chronicleFiles == [listed.id: library.fileURL(characterNumber: valeria, session: listed)])
    }

    /// A character plays an adventure once for credit: a second sheet of it waits, and says so.
    @Test func aSheetWhoseSessionHasASheetAlreadyStaysAndWarns() async throws {
        let store = await store(AccountBox())
        let listed = SessionFactory.session()
        store.keep(UnreportedFactory.reading(code: "6-04"), for: listed, characterNumber: valeria)
        add(UnreportedFactory.reading(code: "6-04"), to: store)
        let record = try record(valeria, in: store)
        #expect(record.unreportedCount == 1)
        let warning = try #require(store.sheetWarnings(for: try sheet(in: store), record: record).first)
        #expect(warning.kind == .adventure)
        #expect(warning.message.contains("paizo.com already lists #6-04: An Enkindled Carnival"))
    }

    /// A sheet scanned on another device: this one has only iCloud's note of the PDF. The data moves at once, so
    /// nothing counts twice, and the PDF follows when it has come down.
    @Test func aSheetWhosePDFIsOnlyInICloudIsFiledAtOnceAndItsPDFFollows() async throws {
        let account = AccountBox()
        let library = library(isInICloud: true)
        let pending = library.pendingURL("123456-2001/a")
        try library.save(Data(), to: ChronicleLibrary.placeholder(of: pending))
        let store = await store(account, library: library)
        store.keep(UnreportedFactory.reading(), for: UnreportedFactory.newSheet(), characterNumber: valeria)

        account.report([reported])
        await store.refresh()

        let record = try record(valeria, in: store)
        #expect(record.unreportedCount == 0)
        #expect(record.level.xp == 8)
        #expect(record.settings.wealth.sheetReadings["777#2"]?.pendingFile == "123456-2001/a")
        #expect(store.chronicleFiles[reported.id] == pending)

        try FileManager.default.removeItem(at: ChronicleLibrary.placeholder(of: pending))
        try pdf.write(to: pending)
        await store.refresh()
        let place = library.fileURL(characterNumber: valeria, session: reported)
        #expect(store.chronicleFiles[reported.id] == place)
        #expect(try Data(contentsOf: place) == pdf)
    }
}
