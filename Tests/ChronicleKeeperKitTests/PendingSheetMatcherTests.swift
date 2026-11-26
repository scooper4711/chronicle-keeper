import Foundation
import Testing
@testable import ChronicleKeeperKit

/// Which reported session an unreported sheet belongs to (R1.15).
struct PendingSheetMatcherTests {
    private func matcher(
        sheets: [String: SheetReading], sessions: [PlayedSession],
        hasSheet: (CharacterRecord.ID, PlayedSession) -> Bool = { _, _ in false }
    ) -> PendingSheetMatcher {
        let roster = UnreportedFactory.roster(sheets: sheets, sessions: sessions)
        return PendingSheetMatcher(characters: roster.characters, hasSheet: hasSheet)
    }

    private func session(_ code: String, number: Int, eventCode: String = "1234", date: Date? = nil) -> PlayedSession {
        SessionFactory.session(
            title: code.hasPrefix("Bounty") ? "Pathfinder \(code): The Hound" : "#\(code): An Adventure",
            date: date ?? Date(timeIntervalSince1970: 1_780_000_000), sessionNumber: number, eventCode: eventCode)
    }

    /// A character plays an adventure once for credit, so the dates say nothing.
    @Test func aSheetGoesToItsCharactersSessionOfTheSameNumberWhateverTheDates() throws {
        let yearsAgo = session("6-05", number: 3, date: Date(timeIntervalSince1970: 1_600_000_000))
        let matcher = matcher(sheets: ["a": UnreportedFactory.reading()], sessions: [yearsAgo])
        let match = try #require(matcher.adoptions.first)
        #expect(matcher.adoptions.count == 1)
        #expect(match.sheet.id == "unreported/a")
        #expect(match.session == yearsAgo)
        #expect(match.from == UnreportedFactory.valeria)
        #expect(match.to == UnreportedFactory.valeria)
        #expect(matcher.elsewhere.isEmpty)
    }

    @Test func aSheetNeverMatchesAnotherScenarioNumber() {
        let matcher = matcher(sheets: ["a": UnreportedFactory.reading()], sessions: [session("6-04", number: 1)])
        #expect(matcher.adoptions.isEmpty)
        #expect(matcher.elsewhere.isEmpty)
    }

    @Test func aSheetWithoutANumberMatchesNothing() {
        let matcher = matcher(
            sheets: ["a": UnreportedFactory.reading(code: nil)], sessions: [session("6-05", number: 1)])
        #expect(matcher.adoptions.isEmpty)
    }

    /// A convention day: four sheets, and the GMs report in any order.
    @Test func eachSheetOfAConventionDayLandsOnItsOwnSession() {
        let codes = ["6-01", "6-02", "6-03", "6-05"]
        let sheets = Dictionary(uniqueKeysWithValues: codes.map { ($0, UnreportedFactory.reading(code: $0)) })
        let reported = [codes[2], codes[0], codes[3], codes[1]].enumerated().map { index, code in
            session(code, number: index + 1)
        }
        let matcher = matcher(sheets: sheets, sessions: reported)
        #expect(matcher.adoptions.count == 4)
        for match in matcher.adoptions {
            #expect("unreported/" + (AdventureClassifier.code(of: match.session.adventure) ?? "") == match.sheet.id)
        }
    }

    @Test func aSessionThatHasASheetKeepsIt() {
        let reported = session("6-05", number: 1)
        let matcher = matcher(sheets: ["a": UnreportedFactory.reading()], sessions: [reported]) { number, session in
            number == UnreportedFactory.valeria && session == reported
        }
        #expect(matcher.adoptions.isEmpty)
    }

    /// Two sheets of one adventure: the one whose event code a session has takes that session, and each session
    /// takes one sheet.
    @Test func twoSheetsOfOneAdventureTakeTheSessionWithTheirEventCodeOrElseTheOldest() throws {
        let sheets = [
            "first": UnreportedFactory.reading(code: "Bounty 19", eventCode: "777"),
            "second": UnreportedFactory.reading(code: "Bounty 19") { $0.playedOn = "2026-06-02" }
        ]
        let older = session("Bounty #19", number: 1, eventCode: "555", date: Date(timeIntervalSince1970: 1_780_000_000))
        let newer = session("Bounty #19", number: 2, eventCode: "777", date: Date(timeIntervalSince1970: 1_780_090_000))
        let matcher = matcher(sheets: sheets, sessions: [newer, older])
        let first = try #require(matcher.adoptions.first { $0.sheet.id == "unreported/first" })
        let second = try #require(matcher.adoptions.first { $0.sheet.id == "unreported/second" })
        #expect(first.session == newer)
        #expect(second.session == older)
    }

    @Test func aSecondSheetOfAnAdventureWithOneSessionKeepsWaiting() {
        let sheets = [
            "first": UnreportedFactory.reading(),
            "second": UnreportedFactory.reading { $0.playedOn = "2026-06-02" }
        ]
        let matcher = matcher(sheets: sheets, sessions: [session("6-05", number: 1)])
        #expect(matcher.adoptions.map(\.sheet.id) == ["unreported/first"])
    }

    // MARK: - Another character

    @Test func aSessionOfAnotherCharacterWithTheNumberAndTheEventCodeIsOfferedNotTaken() throws {
        let pips = UnreportedFactory.pipsSession("#6-05: Ashes Over Highhelm", eventCode: "9999")
        let matcher = matcher(sheets: ["a": UnreportedFactory.reading(eventCode: "9999")], sessions: [pips])
        let match = try #require(matcher.elsewhere.first)
        #expect(matcher.adoptions.isEmpty)
        #expect(match.from == UnreportedFactory.valeria)
        #expect(match.to == UnreportedFactory.pip)
        #expect(match.session == pips)
        #expect(match.id == "elsewhere:123456-2002/9999#2")
    }

    @Test func anotherCharactersSessionNeedsTheEventCodeToo() {
        let pips = UnreportedFactory.pipsSession("#6-05: Ashes Over Highhelm", eventCode: "9999")
        #expect(matcher(sheets: ["a": UnreportedFactory.reading()], sessions: [pips]).elsewhere.isEmpty)
        let other = UnreportedFactory.reading(eventCode: "1111")
        #expect(matcher(sheets: ["a": other], sessions: [pips]).elsewhere.isEmpty)
    }

    @Test func anotherCharactersSessionThatHasASheetIsNotOffered() {
        let pips = UnreportedFactory.pipsSession("#6-05: Ashes Over Highhelm", eventCode: "9999")
        let matcher = matcher(sheets: ["a": UnreportedFactory.reading(eventCode: "9999")], sessions: [pips]) { _, _ in
            true
        }
        #expect(matcher.elsewhere.isEmpty)
    }

    @Test func aCharacterOfAnotherCampaignIsNeverOffered() {
        let starfinder = SessionFactory.session(
            title: "#6-05: Elsewhere",
            points: SessionPoints(achievementPoints: 4, gmCredits: 0, campaign: .starfinder2), sessionNumber: 2,
            eventCode: "9999", characterName: "Zix-7", playerNumber: "123456-701")
        let roster = CharacterRoster(
            summaries: [
                UnreportedFactory.summary(),
                UnreportedFactory.summary("123456-701", name: "Zix-7", campaign: .starfinder2)
            ],
            sessions: [starfinder],
            settings: [UnreportedFactory.valeria: UnreportedFactory.settings(
                ["a": UnreportedFactory.reading(eventCode: "9999")])])
        #expect(PendingSheetMatcher(characters: roster.characters) { _, _ in false }.elsewhere.isEmpty)
    }

    @Test func aSheetWithASessionOfItsOwnIsNotOfferedElsewhere() {
        let own = session("6-05", number: 1, eventCode: "9999")
        let pips = UnreportedFactory.pipsSession("#6-05: An Adventure", eventCode: "9999")
        let matcher = matcher(sheets: ["a": UnreportedFactory.reading(eventCode: "9999")], sessions: [own, pips])
        #expect(matcher.adoptions.map(\.session) == [own])
        #expect(matcher.elsewhere.isEmpty)
    }
}
