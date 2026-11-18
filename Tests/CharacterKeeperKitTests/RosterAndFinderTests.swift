import Foundation
import Testing
@testable import CharacterKeeperKit

struct RosterAndFinderTests {
    private func roster(settings: [String: CharacterSettings] = [:]) throws -> CharacterRoster {
        let summaries = try SummaryPageParser.characters(in: Fixture.text("summary"))
        let sessions = try Fixture.sessionsPage1().sessions + Fixture.sessionsPage2().sessions
        return CharacterRoster(summaries: summaries, sessions: sessions, settings: settings)
    }

    private func character(_ number: String, in roster: CharacterRoster) throws -> CharacterRecord {
        try #require(roster.characters.first { $0.summary.number == number })
    }

    @Test func matchesEverySessionToACharacter() throws {
        let roster = try roster()
        #expect(roster.unmatchedSessions.isEmpty)
        #expect(roster.characters.reduce(0) { $0 + $1.sessions.count } == 77)
    }

    @Test func matchesGameMasterSessionsByNameAndCampaign() throws {
        let record = try character("123456-2002", in: roster())
        #expect(record.sessions.count == 19)
        #expect(record.sessions.contains { $0.session.isGameMaster })
    }

    @Test func calculatesLevels() throws {
        let roster = try roster()
        #expect(try character("123456-2002", in: roster).level.level == 6)
        #expect(try character("123456-2701", in: roster).level.level == 3)
    }

    @Test func aHigherStartingLevelAddsItsXP() throws {
        let started = try roster(settings: ["123456-2002": CharacterSettings(startingLevel: 5)])
        #expect(try character("123456-2002", in: started).level.level == 10)
    }

    @Test func firstEditionCharactersAlwaysStartAtFirstLevel() throws {
        let unchanged = try character("123456-701", in: roster()).level.level
        let started = try roster(settings: ["123456-701": CharacterSettings(startingLevel: 5)])
        #expect(try character("123456-701", in: started).level.level == unchanged)
    }

    @Test func listsSessionsNewestFirst() throws {
        let dates = try character("123456-2002", in: roster()).sessions.compactMap(\.session.date)
        #expect(dates == dates.sorted(by: >))
    }

    @Test func ordersCampaignsForTheSidebar() throws {
        #expect(try roster().campaigns == [.pathfinder2, .starfinder2, .starfinder1])
    }

    @Test func leavesUnknownCharactersUnmatched() throws {
        let sessions = try Fixture.sessionsPage1().sessions
        let roster = CharacterRoster(summaries: [], sessions: sessions)
        #expect(roster.unmatchedSessions.count == 50)
    }

    @Test func catalogHasOneEntryPerAdventure() throws {
        let sessions = try Fixture.sessionsPage1().sessions + Fixture.sessionsPage2().sessions
        let catalog = AdventureCatalog(sessions: sessions)
        #expect(catalog.entries.count == Set(catalog.entries.map(\.id)).count)
        #expect(catalog.search("6-04").count == 1)
        #expect(catalog.search("", campaign: .starfinder2).allSatisfy { $0.campaign == .starfinder2 })
    }

    @Test func finderPutsCharactersWhoPlayedItLast() throws {
        let roster = try roster()
        let catalog = AdventureCatalog(sessions: roster.characters.flatMap { $0.sessions.map(\.session) })
        let adventure = try #require(catalog.search("6-04").first)
        let candidates = AdventureFinder.candidates(for: adventure, in: roster)
        #expect(candidates.count == roster.characters(in: .pathfinder2).count)
        let played = try #require(candidates.last)
        if case .alreadyPlayed = played.eligibility {} else { Issue.record("expected alreadyPlayed last") }
    }

    @Test func finderChecksTheLevelRange() throws {
        let record = try character("123456-2002", in: roster())
        let reference = AdventureReference(
            productID: "new", title: "#9-01: Untouched",
            summary: "A Pathfinder Society Scenario designed for 1st- through 4th-level characters"
        )
        let adventure = AdventureEntry(reference: reference, campaign: .pathfinder2)
        let range = LevelRange(lowest: 1, highest: 4)
        #expect(AdventureFinder.eligibility(of: record, for: adventure) == .outsideLevels(level: 6, range: range))
    }

    @Test func repeatableAdventuresStayEligible() throws {
        let roster = try roster()
        let bountySession = try #require(
            roster.characters.flatMap(\.sessions).first { $0.kind == .bounty }
        )
        var adventure = AdventureEntry(reference: bountySession.session.adventure, campaign: .pathfinder2)
        adventure.isRepeatable = true
        let player = try #require(roster.characters.first { $0.sessions.contains(bountySession) })
        if case .alreadyPlayed = AdventureFinder.eligibility(of: player, for: adventure) {
            Issue.record("a repeatable adventure should not count as played")
        }
    }
}
