import Foundation
import Testing
@testable import ChronicleKeeperKit

/// Chronicle sheets added ahead of their report, for the tests of R1.14 and R1.15: Valeria (2001), who has the
/// fixture's session of #6-04, and Pip (2002).
enum UnreportedFactory {
    static let valeria = "123456-2001"
    static let pip = "123456-2002"

    /// What a sheet of #6-05, played after the fixture's session, is taken to say.
    static func reading(
        code: String? = "6-05", eventCode: String? = nil, _ change: (inout SheetReading) -> Void = { _ in }
    ) -> SheetReading {
        var reading = SheetReading()
        reading.code = code
        reading.eventCode = eventCode
        reading.xp = 4
        reading.funds = 1_400
        reading.playedOn = "2026-06-01"
        reading.addedAt = Date(timeIntervalSince1970: 1_780_400_000)
        change(&reading)
        return reading
    }

    static func summary(
        _ number: String = valeria, name: String = "Valeria Stonebrook", campaign: Campaign = .pathfinder2
    ) -> CharacterSummary {
        CharacterSummary(number: number, campaign: campaign, name: name, factions: [], standing: [])
    }

    static let characters = [summary(), summary(pip, name: "Pip Underbough")]

    /// Settings holding these sheets, by sheet ID.
    static func settings(_ sheets: [String: SheetReading]) -> CharacterSettings {
        var settings = CharacterSettings()
        for (id, reading) in sheets { settings.wealth.sheetReadings[UnreportedSheet.key(id)] = reading }
        return settings
    }

    /// Both characters, with Valeria's sheets and the sessions paizo.com lists.
    static func roster(
        sheets: [String: SheetReading], sessions: [PlayedSession] = [SessionFactory.session()]
    ) -> CharacterRoster {
        CharacterRoster(summaries: characters, sessions: sessions, settings: [valeria: settings(sheets)])
    }

    /// A session paizo.com lists for Pip.
    static func pipsSession(_ title: String, eventCode: String, sessionNumber: Int = 2) -> PlayedSession {
        SessionFactory.session(
            title: title, sessionNumber: sessionNumber, eventCode: eventCode, characterName: "Pip Underbough",
            playerNumber: pip)
    }

    /// The session a sheet being added stands for, before anything is kept for it.
    static func newSheet(_ id: String = "a", for number: String = valeria) -> PlayedSession {
        UnreportedSheet.session(id: id, reading: SheetReading(), for: summary(number))
    }
}

/// The account a store reads, which a test changes to stand for a GM reporting a session.
final class AccountBox: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: AccountSnapshot

    init(sessions: [PlayedSession] = [SessionFactory.session()]) {
        snapshot = Self.account(sessions)
    }

    var value: AccountSnapshot { lock.withLock { snapshot } }

    func report(_ sessions: [PlayedSession]) {
        lock.withLock { snapshot = Self.account(snapshot.sessions + sessions) }
    }

    private static func account(_ sessions: [PlayedSession]) -> AccountSnapshot {
        AccountSnapshot(
            characters: UnreportedFactory.characters, sessions: sessions,
            fetchedAt: Date(timeIntervalSince1970: 1_780_500_000))
    }
}

/// What the store tests of unreported sheets share: a store on an account a test can change, with a library.
@MainActor
protocol UnreportedStoreTesting {}

extension UnreportedStoreTesting {
    var valeria: String { UnreportedFactory.valeria }
    var pip: String { UnreportedFactory.pip }
    var pdf: Data { Data("%PDF-1.4 a chronicle".utf8) }
    var key: String { "unreported/a" }

    /// The session the GM reports for the sheet.
    var reported: PlayedSession {
        SessionFactory.session(title: "#6-05: Ashes Over Highhelm", sessionNumber: 2, eventCode: "777")
    }

    func library(isInICloud: Bool = false) -> ChronicleLibrary {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("unreported-store-tests-\(UUID().uuidString)")
        return ChronicleLibrary(folder: folder, isInICloud: isInICloud)
    }

    func store(_ account: AccountBox, library: ChronicleLibrary? = nil) async -> CharacterStore {
        let store = CharacterStore(repository: InMemoryCharacterRepository()) { account.value }
        await store.refresh()
        store.useChronicleLibrary(library ?? self.library())
        return store
    }

    /// Adds a sheet as the confirmation does: the PDF, then what was read.
    func add(_ reading: SheetReading, to store: CharacterStore, id: String = "a") {
        let sheet = UnreportedFactory.newSheet(id)
        store.attachChronicle(pdf, to: sheet, characterNumber: valeria)
        store.keep(reading, for: sheet, characterNumber: valeria)
    }

    func record(_ number: String, in store: CharacterStore) throws -> CharacterRecord {
        try #require(store.roster.characters.first { $0.id == number })
    }

    /// Valeria's unreported sheet, as the roster shows it.
    func sheet(in store: CharacterStore) throws -> PlayedSession {
        try #require(try record(valeria, in: store).sessions.first { !$0.isReported }).session
    }
}
