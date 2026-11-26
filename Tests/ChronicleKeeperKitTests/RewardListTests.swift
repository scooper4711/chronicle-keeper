import Foundation
import Testing
@testable import ChronicleKeeperKit

@Suite("Reward point types")
struct RewardPointTypeTests {
    @Test("The free lists' point types name a kind and a campaign")
    func freeListsAreRead() throws {
        let boons = try #require(RewardPointType("Chronicle Boons - PFS(2ed)"))
        #expect(boons.kind == .chronicleBoon)
        #expect(boons.campaign == .pathfinder2)
        let rewards = try #require(RewardPointType("Game Rewards - SFS"))
        #expect(rewards.kind == .gameReward)
        #expect(rewards.campaign == .starfinder1)
    }

    @Test("Point types that are spent, or of an unknown campaign, are no free list", arguments: [
        "Achievement Points - PFS(2ed)", "Achievement Points - SFS2", "Playtest Points", "Game Rewards - PACS", ""
    ])
    func otherPointTypesAreLeftOut(text: String) {
        #expect(RewardPointType(text) == nil)
    }
}

@Suite("Reward list parser")
struct RewardListParserTests {
    @Test("The Boons tab links to the four free lists, and the lists that cost points are left out")
    func findsTheFreeLists() throws {
        let links = try RewardListParser.links(in: Fixture.text("boons"))
        let titles = [
            "Chronicle Boons - PFS(2ed)", "Game Rewards - PFS(2ed)", "Chronicle Boons - SFS", "Game Rewards - SFS"
        ]
        let campaigns: [Campaign] = [.pathfinder2, .pathfinder2, .starfinder1, .starfinder1]
        #expect(links.map(\.title) == titles)
        #expect(links.map(\.type.campaign) == campaigns)
        #expect(links[1].link.containerID == "_2")
        #expect(links[1].link.path == "/cgi-bin/WebObjects/Store.woa/1/ajax/SESSIONTEST/0.Rewards.2.9.0.1.1")
    }

    @Test("A page without lists has no links")
    func aPageWithoutListsHasNone() throws {
        #expect(try RewardListParser.links(in: "<html><body><p>Boons you have purchased:</p></body></html>").isEmpty)
    }

    @Test("A list's link without an Ajax target means the page changed")
    func aLinkWithoutATargetIsAnError() {
        let html = #"<a href="/somewhere">Rewards purchaseable with Game Rewards - SFS (click to expand)</a>"#
        #expect(throws: ParsingError.self) { try RewardListParser.links(in: html) }
    }

    @Test("An opened list gives each row's name and description, with its kind and campaign")
    func readsAnOpenedList() throws {
        let offers = try RewardListParser.offers(
            in: Fixture.text("reward-list-chronicle-pfs2-ajax"), list: "Chronicle Boons - PFS(2ed)")
        #expect(offers.count == 8)
        #expect(offers.allSatisfy { $0.kind == .chronicleBoon && $0.campaign == .pathfinder2 })
        #expect(offers[0].name == "PFS (2ed) Scenario #1–04: Bandits of Immenwood Boon A")
        #expect(offers[4].name == "PFS (2ed) Scenario #4-03: Stalwart Shield")
        let summary = "Gain access to an intelligent shield. Must have played Linnorm's Legacy to download."
        #expect(offers[4].summary == summary)
        #expect(Set(offers.map(\.id)).count == 8)
    }

    @Test("Game Rewards and the Starfinder lists read the same way")
    func readsTheOtherLists() throws {
        let game = try RewardListParser.offers(in: Fixture.text("reward-list-game-pfs2-ajax"), list: "Game Rewards")
        #expect(game.map(\.name).contains("Master Hireling"))
        #expect(game.allSatisfy { $0.kind == .gameReward && $0.campaign == .pathfinder2 })
        let starfinder = try RewardListParser.offers(
            in: Fixture.text("reward-list-game-sfs-ajax"), list: "Game Rewards - SFS")
        #expect(starfinder.count == 2)
        #expect(starfinder.allSatisfy { $0.campaign == .starfinder1 })
    }

    @Test("Rows that cost points, or of another point type, are left out")
    func leavesOutWhatIsNotFree() throws {
        let html = """
            <table><tr><th>Name</th><th>Description</th><th>Price</th><th>Point Type</th><th>Character</th></tr>
            <tr><td>Free</td><td>Is free.</td><td><div>0</div></td><td>Game Rewards - PFS(2ed)</td><td></td></tr>
            <tr><td>Costly</td><td>Costs.</td><td><div>4</div></td><td>Game Rewards - PFS(2ed)</td><td></td></tr>
            <tr><td>Spent</td><td>Spent.</td><td><div>0</div></td><td>Achievement Points - PFS(2ed)</td><td></td></tr>
            <tr><td></td><td>Nameless.</td><td><div>0</div></td><td>Game Rewards - PFS(2ed)</td><td></td></tr>
            </table>
            """
        #expect(try RewardListParser.offers(in: html, list: "Game Rewards").map(\.name) == ["Free"])
    }

    @Test("The reward table is found inside the page's layout table")
    func findsTheTableInsideALayoutTable() throws {
        let inner = try Fixture.text("reward-list-game-sfs-ajax")
        let html = "<table><tr><td>Menu</td><td>\(inner)</td></tr></table>"
        #expect(try RewardListParser.offers(in: html, list: "Game Rewards - SFS").count == 2)
    }

    @Test("An answer without the table means the page changed, and says which list")
    func anAnswerWithoutATableIsAnError() {
        #expect(throws: ParsingError(
            operation: "Reading the list of Game Rewards - SFS", reason: "the list has no table of rewards")
        ) {
            try RewardListParser.offers(in: "<p>Please sign in.</p>", list: "Game Rewards - SFS")
        }
    }
}
