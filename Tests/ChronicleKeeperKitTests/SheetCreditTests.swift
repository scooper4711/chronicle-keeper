import Foundation
import Testing
@testable import ChronicleKeeperKit

/// A chronicle sheet's XP as a source for its session's XP and track (R2.11), and where its reading is kept.
struct SheetCreditTests {
    private let pathfinder = ProgressCalculator(campaign: .pathfinder2)

    private func settings(sheetXP: Double?, for session: PlayedSession) -> CharacterSettings {
        var reading = SheetReading()
        reading.xp = sheetXP
        var settings = CharacterSettings()
        settings.wealth.sheetReadings[session.keyWithinCharacter] = reading
        return settings
    }

    @Test func theSheetsXPWinsOverWhatTheReputationImplies() {
        let session = SessionFactory.session(reputation: 4)
        let progress = pathfinder.progress(of: session, settings: settings(sheetXP: 2, for: session))
        #expect(progress.xp == 2)
        #expect(progress.xpSource == .chronicle)
        #expect(progress.track == .slow)
        #expect(progress.trackSource == .chronicle)
    }

    @Test func theFullAmountMeansNormalTrack() {
        let session = SessionFactory.session(reputation: 2)
        let progress = pathfinder.progress(of: session, settings: settings(sheetXP: 4, for: session))
        #expect(progress.xp == 4)
        #expect(progress.track == .normal)
        #expect(progress.trackSource == .chronicle)
    }

    @Test func xpTheAdventureCannotGiveIsNotCounted() {
        let session = SessionFactory.session(reputation: 4)
        let progress = pathfinder.progress(of: session, settings: settings(sheetXP: 9, for: session))
        #expect(progress.xp == 4)
        #expect(progress.xpSource == .rules)
        #expect(progress.trackSource == .inferred)
    }

    @Test func anUnreadXPChangesNothing() {
        let session = SessionFactory.session(reputation: 4)
        let with = pathfinder.progress(of: session, settings: settings(sheetXP: nil, for: session))
        #expect(with == pathfinder.progress(of: session, settings: CharacterSettings()))
    }

    @Test func theUsersOwnCorrectionBeatsTheSheet() {
        let session = SessionFactory.session(reputation: 4)
        var settings = settings(sheetXP: 2, for: session)
        settings.setOverride(SessionOverride(track: .normal), for: session)
        let progress = pathfinder.progress(of: session, settings: settings)
        #expect(progress.xp == 4)
        #expect(progress.trackSource == .override)
        #expect(progress.xpSource == .rules)
    }

    /// An adventure whose kind has no rule: the sheet's XP replaces the estimate, and the track stays as it was.
    @Test func theSheetReplacesAnEstimate() {
        let session = SessionFactory.session(title: "Free RPG Day Adventure", summary: "", reputation: nil)
        let progress = pathfinder.progress(of: session, settings: settings(sheetXP: 12, for: session))
        #expect(progress.xp == 12)
        #expect(progress.xpSource == .chronicle)
        #expect(progress.trackSource != .chronicle)
    }

    @Test func readingsAreSavedWithTheLedgerAndMergePerSheet() throws {
        var reading = SheetReading()
        reading.xp = 4
        var local = CharacterWealth()
        local.sheetReadings["1234#1"] = reading
        var remote = CharacterWealth()
        remote.sheetReadings["1234#2"] = reading
        let merged = WealthMerge.merge(local: local, remote: remote, ancestor: CharacterWealth())
        #expect(Set(merged.sheetReadings.keys) == ["1234#1", "1234#2"])
        let again = try JSONDecoder().decode(CharacterWealth.self, from: JSONEncoder().encode(merged))
        #expect(again == merged)
    }

    @Test func aLedgerWithoutSheetsIsSavedAsBefore() throws {
        let saved = try #require(String(bytes: try JSONEncoder().encode(CharacterWealth()), encoding: .utf8))
        #expect(!saved.contains("sheetReadings"))
        let older = try JSONDecoder().decode(CharacterWealth.self, from: Data(#"{"earned":{}}"#.utf8))
        #expect(older.sheetReadings.isEmpty)
    }
}
