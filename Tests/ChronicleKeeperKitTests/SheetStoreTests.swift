import Foundation
import Testing
@testable import ChronicleKeeperKit

/// Keeping what was read from a session's chronicle sheet, and the ledger's gold it fills (R1.11, R1.12, R5.11).
@MainActor
struct SheetStoreTests {
    private let number = "123456-2001"
    private let session = SessionFactory.session()
    private var key: String { session.keyWithinCharacter }

    private func store() async -> CharacterStore {
        let store = CharacterStore(repository: InMemoryCharacterRepository()) { SnapshotFactory.snapshot() }
        await store.refresh()
        return store
    }

    private func reading(xp: Double? = 4, funds: Int? = 1_120, part: String? = "2001") -> SheetReading {
        var reading = SheetReading()
        reading.xp = xp
        reading.funds = funds
        reading.characterPart = part
        return reading
    }

    @Test func readingAPDFGivesItsValuesAndWhereTheyAre() async throws {
        let store = await store()
        let located = await store.read(try SheetPDFFactory.pdf(SheetPDFFactory.filledSheet()))
        #expect(located.reading.xp == 4)
        #expect(located.reading.funds == 1_120)
        #expect(Set(located.places.keys) == [.characterNumber, .xp, .funds])
    }

    @Test func keepingAReadingFillsTheEmptyGoldField() async {
        let store = await store()
        store.keep(reading(), for: session, characterNumber: number)
        #expect(store.sheetReading(for: session, characterNumber: number)?.xp == 4)
        #expect(store.settings(for: number).wealth.earned[key] == 1_120)
    }

    @Test func goldTheUserTypedIsNeverReplaced() async throws {
        let store = await store()
        store.update(number) { $0.wealth.earned[key] = 2_000 }
        store.keep(reading(), for: session, characterNumber: number)
        #expect(store.settings(for: number).wealth.earned[key] == 2_000)
        let warning = try #require(store.sheetWarnings(for: session, record: store.roster.characters[0]).first)
        #expect(warning.kind == .funds)
    }

    @Test func aSheetWithoutGoldLeavesTheFieldEmpty() async {
        let store = await store()
        store.keep(reading(funds: nil), for: session, characterNumber: number)
        #expect(store.settings(for: number).wealth.earned[key] == nil)
    }

    /// Gold a reading filled in is the sheet's, not typed: the sheet read again and corrected replaces it.
    @Test func aCorrectedReadingReplacesTheGoldTheEarlierOneFilledIn() async {
        let store = await store()
        store.keep(reading(funds: 1_120), for: session, characterNumber: number)
        store.keep(reading(funds: 1_420), for: session, characterNumber: number)
        #expect(store.settings(for: number).wealth.earned[key] == 1_420)
        store.keep(reading(funds: nil), for: session, characterNumber: number)
        #expect(store.settings(for: number).wealth.earned[key] == 1_420)
    }

    @Test func theUserCanTakeTheSheetsAmount() async {
        let store = await store()
        store.update(number) { $0.wealth.earned[key] = 2_000 }
        store.keep(reading(), for: session, characterNumber: number)
        store.useSheetAmount(for: session, characterNumber: number)
        #expect(store.settings(for: number).wealth.earned[key] == 1_120)
        #expect(store.sheetWarnings(for: session, record: store.roster.characters[0]).isEmpty)
    }

    @Test func takingTheAmountOfASheetWithoutOneChangesNothing() async {
        let store = await store()
        store.update(number) { $0.wealth.earned[key] = 2_000 }
        store.useSheetAmount(for: session, characterNumber: number)
        #expect(store.settings(for: number).wealth.earned[key] == 2_000)
    }

    @Test func aClearedWarningStaysClearedWhenTheSameValueIsKeptAgain() async throws {
        let store = await store()
        let misread = reading(part: "2002")
        store.keep(misread, for: session, characterNumber: number)
        let warning = try #require(store.sheetWarnings(for: session, record: store.roster.characters[0]).first)
        #expect(warning.kind == .character)
        store.clearWarning(warning.id, for: session, characterNumber: number)
        #expect(store.sheetWarnings(for: session, record: store.roster.characters[0]).isEmpty)
        store.keep(misread, for: session, characterNumber: number)
        #expect(store.sheetWarnings(for: session, record: store.roster.characters[0]).isEmpty)
        store.keep(reading(part: "2702"), for: session, characterNumber: number)
        #expect(store.sheetWarnings(for: session, record: store.roster.characters[0]).count == 1)
    }

    @Test func theSheetsXPCountsOnceItIsKept() async {
        let store = await store()
        store.keep(reading(xp: 2), for: session, characterNumber: number)
        let progress = store.roster.characters[0].sessions[0]
        #expect(progress.xp == 2)
        #expect(progress.xpSource == .chronicle)
    }

    @Test func removingTheSheetForgetsTheReadingAndKeepsTheGoldAndCorrections() async {
        let store = await store()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("chronicle-sheet-store-tests-\(UUID().uuidString)")
        store.useChronicleLibrary(ChronicleLibrary(folder: folder))
        store.attachChronicle(Data("%PDF-1.4".utf8), to: session, characterNumber: number)
        store.keep(reading(), for: session, characterNumber: number)
        store.update(number) { $0.setOverride(SessionOverride(track: .slow), for: session) }
        store.removeChronicle(from: session, characterNumber: number)
        let settings = store.settings(for: number)
        #expect(settings.wealth.sheetReadings[key] == nil)
        #expect(settings.wealth.earned[key] == 1_120)
        #expect(settings.override(for: session)?.track == .slow)
    }

    @Test func removingASheetThatWasNeverReadSavesNothing() async {
        let store = await store()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("chronicle-sheet-store-tests-\(UUID().uuidString)")
        store.useChronicleLibrary(ChronicleLibrary(folder: folder))
        store.attachChronicle(Data("%PDF-1.4".utf8), to: session, characterNumber: number)
        var changed: [String] = []
        store.onLocalChange = { changed.append($0) }
        store.removeChronicle(from: session, characterNumber: number)
        #expect(changed.isEmpty)
    }
}
