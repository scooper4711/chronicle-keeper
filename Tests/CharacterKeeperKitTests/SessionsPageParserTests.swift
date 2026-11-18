import Foundation
import Testing
@testable import CharacterKeeperKit

struct SessionsPageParserTests {
    @Test func readsTheFirstPage() throws {
        let page = try Fixture.sessionsPage1()
        #expect(page.sessions.count == 50)
        #expect(page.range == PageRange(first: 1, last: 50, total: 77))
        let next = try #require(page.nextPage)
        #expect(next.path.hasPrefix("/cgi-bin/WebObjects/Store.woa/1/ajax/"))
        #expect(next.containerID.hasPrefix("auc_"))
    }

    @Test func readsTheLastPageFromTheAjaxFragment() throws {
        let page = try Fixture.sessionsPage2()
        #expect(page.sessions.count == 27)
        #expect(page.range?.isLastPage == true)
        #expect(page.nextPage == nil)
    }

    @Test func readsAGameMasterRow() throws {
        let session = try #require(try Fixture.sessionsPage1().sessions.first)
        #expect(session.isGameMaster)
        #expect(session.campaign == .starfinder2)
        #expect(session.points.achievementPoints == 8)
        #expect(session.points.gmCredits == 1)
        #expect(session.reputation == 2)
        #expect(session.faction.isEmpty)
        #expect(session.characterNumber == nil)
        #expect(session.sessionNumber == 5)
        #expect(session.adventure.title == "Starfinder Society Scenario #1-10: Rites of Rekindling")
        #expect(session.adventure.productID == "btq0e8yu")
        #expect(session.date == ISO8601DateFormatter().date(from: "2026-11-07T08:00:00Z"))
    }

    @Test func readsAPlayedRow() throws {
        let sessions = try Fixture.sessionsPage1().sessions
        let played = try #require(sessions.first { $0.campaign == .pathfinder2 && !$0.isGameMaster })
        #expect(played.characterNumber?.hasPrefix("123456-20") == true)
        #expect(played.reputation != nil)
        #expect(!played.faction.isEmpty)
        #expect(played.gameMaster.hasPrefix("Game Master"))
    }

    @Test func keepsRowsWithoutADate() throws {
        let sessions = try Fixture.sessionsPage2().sessions
        #expect(sessions.filter { $0.date == nil }.count == 4)
    }

    @Test func everyRowHasACampaignAndAnAdventure() throws {
        let sessions = try Fixture.sessionsPage1().sessions + Fixture.sessionsPage2().sessions
        #expect(sessions.allSatisfy { if case .other = $0.campaign { false } else { true } })
        #expect(sessions.allSatisfy { !$0.adventure.title.isEmpty })
        #expect(Set(sessions.map(\.id)).count == 77)
    }

    @Test func rejectsANextLinkWithoutAnAjaxTarget() {
        let html = #"<a href="/next">next &gt;</a>"#
        #expect(throws: ParsingError.self) { try SessionsPageParser.page(from: html) }
    }
}
