import Foundation
import Testing
@testable import ChronicleKeeperKit

/// The warnings a chronicle sheet raises against its session and the ledger (R1.12).
struct SheetCheckerTests {
    private let number = "123456-2001"
    private let session = SessionFactory.session(reputation: 4)

    /// Valeria (2001), who played the session, and Pip (2002), with what Valeria's sheet and ledger hold.
    private func checker(
        _ reading: SheetReading? = nil, earned: Int? = nil, campaign: Campaign = .pathfinder2,
        session: PlayedSession? = nil
    ) -> SheetChecker {
        let session = session ?? self.session
        var settings = CharacterSettings()
        settings.wealth.sheetReadings[session.keyWithinCharacter] = reading
        settings.wealth.earned[session.keyWithinCharacter] = earned
        let roster = CharacterRoster(
            summaries: [
                CharacterSummary(number: number, campaign: campaign, name: "Valeria", factions: [], standing: []),
                CharacterSummary(number: "123456-2002", campaign: campaign, name: "Pip", factions: [], standing: [])
            ],
            sessions: [session], settings: [number: settings])
        return SheetChecker(record: roster.characters[0], roster: roster)
    }

    private func reading(_ change: (inout SheetReading) -> Void) -> SheetReading {
        var reading = SheetReading()
        change(&reading)
        return reading
    }

    private func kinds(_ reading: SheetReading, earned: Int? = nil) -> [SheetMismatch.Kind] {
        checker(reading, earned: earned).warnings(for: session).map(\.kind)
    }

    @Test func aSheetThatAgreesRaisesNothing() {
        let agreeing = reading {
            $0.code = "6-04"
            $0.playerNumber = "123456"
            $0.characterPart = "2001"
            $0.xp = 4
            $0.funds = 2000
        }
        #expect(kinds(agreeing, earned: 2000).isEmpty)
    }

    @Test func aSessionWithoutAReadingRaisesNothing() {
        #expect(checker().warnings(for: session).isEmpty)
    }

    @Test func anUnreadFieldRaisesNothing() {
        #expect(kinds(SheetReading(), earned: 2000).isEmpty)
    }

    // MARK: - Character

    @Test func anotherCharactersPartWarnsAndNamesBoth() throws {
        let warning = try #require(checker(reading { $0.characterPart = "2002" }).warnings(for: session).first)
        #expect(warning.kind == .character)
        #expect(warning.message == "The sheet is for character number 2002, Pip. "
            + "paizo.com reported this session for 2001, Valeria.")
    }

    @Test func aPartNoCharacterHasIsNamedByNumberOnly() throws {
        let warning = try #require(checker(reading { $0.characterPart = "2702" }).warnings(for: session).first)
        #expect(warning.message.hasPrefix("The sheet is for character number 2702. "))
    }

    /// Recognition misread a digit of the real sheet's Organized Play number with full confidence.
    @Test func aDifferentOrganizedPlayNumberAloneDoesNotWarn() {
        #expect(kinds(reading { $0.playerNumber = "123451"; $0.characterPart = "2001" }).isEmpty)
    }

    // MARK: - Adventure

    @Test func anotherAdventuresCodeWarns() throws {
        let warning = try #require(checker(reading { $0.code = "6-05" }).warnings(for: session).first)
        #expect(warning.kind == .adventure)
        #expect(warning.message == "The sheet is for 6-05. This session is #6-04: An Enkindled Carnival.")
    }

    @Test func aSessionWithoutACodeIsNotCompared() {
        let unnumbered = SessionFactory.session(title: "Free RPG Day Adventure", summary: "")
        let checker = checker(reading { $0.code = "6-05" }, session: unnumbered)
        #expect(checker.warnings(for: unnumbered).isEmpty)
    }

    // MARK: - XP

    @Test func xpThatDiffersFromTheRecordWarns() throws {
        let warning = try #require(checker(reading { $0.xp = 2 }).warnings(for: session).first)
        #expect(warning.kind == .xp)
        #expect(warning.message == "The sheet gives 2 XP. paizo.com's record gives 4.")
    }

    @Test func xpTheAdventureCannotGiveSaysItIsNotCounted() throws {
        let warning = try #require(checker(reading { $0.xp = 9 }).warnings(for: session).first)
        #expect(warning.kind == .xp)
        #expect(warning.message.hasSuffix("which this adventure can't give, so it isn't counted."))
    }

    /// Reputation that is neither the full amount nor its half says nothing of the track, so the record's XP is
    /// a guess from the character's default track.
    @Test func aRecordThatOnlyGuessesIsNotCompared() {
        let unclear = SessionFactory.session(reputation: 3)
        let checker = checker(reading { $0.xp = 2 }, session: unclear)
        #expect(checker.warnings(for: unclear).isEmpty)
    }

    @Test func anEstimatedXPIsNotCompared() {
        let unruled = SessionFactory.session(title: "Free RPG Day Adventure", summary: "", reputation: nil)
        let checker = checker(reading { $0.xp = 12 }, session: unruled)
        #expect(checker.warnings(for: unruled).isEmpty)
    }

    // MARK: - Gold

    @Test func goldThatDiffersFromTheLedgerWarnsInTheCampaignsMoney() throws {
        let warning = try #require(checker(reading { $0.funds = 2200 }, earned: 2000).warnings(for: session).first)
        #expect(warning.kind == .funds)
        #expect(warning.message.contains("gp"))
        let credits = checker(reading { $0.funds = 2200 }, earned: 2000, campaign: .starfinder2)
        #expect(credits.warnings(for: session).first?.message.contains("credits") == true)
    }

    @Test func anEmptyLedgerFieldNeverDisagrees() {
        #expect(kinds(reading { $0.funds = 2200 }).isEmpty)
    }

    // MARK: - Clearing

    @Test func aClearedWarningStaysAwayUntilTheSheetSaysSomethingElse() throws {
        var misread = reading { $0.characterPart = "2002"; $0.xp = 2 }
        let ids = checker(misread).warnings(for: session).map(\.id)
        #expect(ids == ["character:2002", "xp:2.0"])
        misread.clearedWarnings = Set(ids)
        #expect(kinds(misread).isEmpty)
        misread.characterPart = "2702"
        #expect(kinds(misread) == [.character])
    }

    @Test func theConfirmationSeesClearedMismatchesToo() {
        var misread = reading { $0.characterPart = "2002" }
        misread.clearedWarnings = ["character:2002"]
        #expect(checker(misread).mismatches(of: misread, with: session).map(\.kind) == [.character])
    }
}
