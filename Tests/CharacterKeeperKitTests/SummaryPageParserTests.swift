import Testing
@testable import CharacterKeeperKit

struct SummaryPageParserTests {
    @Test func readsEveryCharacter() throws {
        let characters = try SummaryPageParser.characters(in: Fixture.text("summary"))
        #expect(characters.count == 9)
        #expect(characters.map(\.campaign).filter { $0 == .pathfinder2 }.count == 5)
    }

    @Test func readsFactionsAndFame() throws {
        let characters = try SummaryPageParser.characters(in: Fixture.text("summary"))
        let character = try #require(characters.first { $0.number == "123456-2002" })
        #expect(character.campaign == .pathfinder2)
        #expect(character.factions.map(\.name) == ["Envoy's Alliance", "Horizon Hunters", "Verdant Wheel", "Vigilant Seal"])
        #expect(character.factions[1].value == 68)
        #expect(character.standing == [NamedValue(name: "Fame", value: 89)])
    }

    @Test func readsStarfinderFirstEditionTotalReputation() throws {
        let characters = try SummaryPageParser.characters(in: Fixture.text("summary"))
        let character = try #require(characters.first { $0.campaign == .starfinder1 })
        #expect(character.standing.map(\.name) == ["Total Reputation"])
    }

    @Test func leavesStarfinderSecondEditionWithoutStanding() throws {
        let characters = try SummaryPageParser.characters(in: Fixture.text("summary"))
        let starfinder = characters.filter { $0.campaign == .starfinder2 }
        #expect(starfinder.count == 3)
        #expect(starfinder.allSatisfy { $0.factions.isEmpty && $0.standing.isEmpty })
    }

    @Test func ignoresPagesWithoutCharacters() throws {
        #expect(try SummaryPageParser.characters(in: "<html><body><p>Sign in</p></body></html>").isEmpty)
    }
}
