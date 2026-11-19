import Foundation
import Testing
@testable import ChronicleKeeperKit

/// A scenario the way Warhorn's API answers with it.
struct Listed: Sendable {
    var name: String
    var campaign: String? = "PFS2"
    var levels: [Int?] = [1, 4]
    var tags: [String] = []
    var isCustom = false
    var cover: String?

    var json: [String: Any] {
        [
            "name": name, "minLevel": levels[0] ?? NSNull(), "maxLevel": levels[1] ?? NSNull(), "isCustom": isCustom,
            "coverArtUrl": cover ?? NSNull(), "campaign": campaign.map { ["code": $0] } ?? NSNull(),
            "tags": tags.map { ["name": $0] }
        ]
    }

    func scenario() throws -> WarhornScenario {
        try JSONDecoder().decode(WarhornScenario.self, from: JSONSerialization.data(withJSONObject: json))
    }
}

/// Stands in for warhorn.net: answers each search text with its pages, and records what was asked.
private final class WarhornStub: HTTPClient, @unchecked Sendable {
    struct Asked: Equatable {
        let text: String
        let after: String?
    }

    private let lock = NSLock()
    private var pages: [String: [[Listed]]] = [:]
    private var asked: [Asked] = []
    private var sent: [URLRequest] = []
    var status = 200
    /// Every page claims another one follows, as a search with endless matches would.
    var isEndless = false

    func answer(_ text: String, pages: [[Listed]]) {
        lock.withLock { self.pages[text] = pages }
    }

    var questions: [Asked] { lock.withLock { asked } }
    var requests: [URLRequest] { lock.withLock { sent } }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        let variables = body?["variables"] as? [String: Any] ?? [:]
        let question = Asked(text: variables["query"] as? String ?? "", after: variables["after"] as? String)
        let listed = lock.withLock { () -> [[Listed]] in
            asked.append(question)
            sent.append(request)
            return pages[question.text] ?? [[]]
        }
        let index = Int(question.after ?? "0") ?? 0
        let hasNext = isEndless || index + 1 < listed.count
        let reply: [String: Any] = ["data": ["globalScenarios": [
            "nodes": listed[min(index, listed.count - 1)].map(\.json),
            "pageInfo": ["hasNextPage": hasNext, "endCursor": "\(index + 1)"]
        ]]]
        return HTTPResponse(data: try JSONSerialization.data(withJSONObject: reply), statusCode: status)
    }
}

struct WarhornScenarioTests {
    @Test func aScenarioBecomesAnAdventure() throws {
        let listed = Listed(
            name: "PFS2 6-04: An Enkindled Carnival", levels: [3, 6], tags: ["Metaplot"],
            cover: "https://cdn.paizo.com/cover.jpg")
        let entry = AdventureEntry(published: try #require(try listed.scenario().adventure))
        #expect(entry.title == "#6-04: An Enkindled Carnival")
        #expect(entry.code == "6-04")
        #expect(entry.campaign == .pathfinder2)
        #expect(entry.kind == .scenario)
        #expect(entry.levelRange == LevelRange(lowest: 3, highest: 6))
        #expect(!entry.isRepeatable)
        #expect(entry.coverArt == URL(string: "https://cdn.paizo.com/cover.jpg"))
    }

    @Test func aCoverKeptOutsidePaizoAndWarhornIsLeftOut() throws {
        let listed = Listed(name: "PFS2 6-04: An Enkindled Carnival", cover: "https://i.imgur.com/cover.png")
        let adventure = try #require(try listed.scenario().adventure)
        #expect(adventure.coverArt == nil)
    }

    @Test(arguments: [
        ("PF2 Bounty 10: Hillcross Roundup", "Bounty #10: Hillcross Roundup"),
        ("PFS2 Quest (Series 2) #14: The Swordlord’s Challenge", "Quest (Series 2) #14: The Swordlord’s Challenge"),
        ("PFS2 Intro 1: The Second Confirmation", "Intro #1: The Second Confirmation"),
        ("SF1 One-Shot #1: Band on the Run", "One-Shot #1: Band on the Run"),
        ("PFS Special: Ruins of Bonekeep, Level 1: The Silent Grave",
         "Special: Ruins of Bonekeep, Level 1: The Silent Grave"),
        ("PFS1 4-EX: Day of the Demon", "#4-EX: Day of the Demon"),
        ("SFS1 1-16: Dreaming of the Future", "#1-16: Dreaming of the Future"),
        ("Pathfinder Beginner Box: Secrets of the Unlit Star", "Pathfinder Beginner Box: Secrets of the Unlit Star")
    ])
    func spellsTitlesTheWayTheSessionsTabDoes(name: String, title: String) {
        #expect(WarhornScenario.title(from: name) == title)
    }

    @Test func readsTheCodeAndKindOfQuestsAndBounties() throws {
        let bounty = AdventureEntry(published: try #require(
            try Listed(name: "PF2 Bounty 10: Hillcross Roundup", levels: [1, 1]).scenario().adventure))
        let quest = AdventureEntry(published: try #require(
            try Listed(name: "PFS2 Quest (Series 2) #14: The Swordlord’s Challenge", tags: ["Repeatable"])
                .scenario().adventure))
        #expect(bounty.code == "Bounty 10")
        #expect(bounty.kind == .bounty)
        #expect(bounty.isRepeatable)
        #expect(bounty.levelRange?.displayText == "Level 1")
        #expect(quest.code == "Quest 14")
        #expect(quest.kind == .questSeries2)
        #expect(quest.isRepeatable)
        let played = SessionFactory.session(title: "Pathfinder Quest (Series 2) #14: The Swordlord’s Challenge")
        #expect(quest.matches(played))
    }

    @Test(arguments: [
        ("#7-01: Intro: Year of Battle's Spark", AdventureKind.scenario),
        ("Intro #1: The Second Confirmation", .scenario),
        ("Quest #9: Wayfinder Origins", .questSeries1),
        ("Bounty #10: Hillcross Roundup", .bounty),
        ("Adventure: The Fall of Plaguestone, Part 2: The Ranger's Request", .adventure),
        ("AP 175: Quest for the Frozen Flame, Part 1: Broken Tusk Moon", .adventure),
        ("Mod: We Be Goblins!", .adventure),
        ("One-Shot #1: Sundered Waves", .other)
    ])
    func tellsAPublishedAdventuresKindFromItsTitle(title: String, kind: AdventureKind) {
        #expect(AdventureClassifier.kind(ofPublished: title) == kind)
    }

    @Test(arguments: [
        Listed(name: "PFS 6-04: Beacon Below - subtier 7-8", isCustom: true),
        Listed(name: "DDAL-DRW-09 Vile Bounty", campaign: "DDAL"),
        Listed(name: "#6-04 Bacon Below", campaign: nil),
        Listed(name: "PFS2: Scenario Pending"),
        Listed(name: "SFS2 Infinite Scenario (L1-2)", campaign: "SFS2")
    ])
    func leavesOutWhatPaizoDidNotPublish(listed: Listed) throws {
        #expect(try listed.scenario().adventure == nil)
    }

    @Test(arguments: [([5, nil], "Level 5"), ([nil, 3], "Level 3"), ([nil, nil], ""), ([0, 0], "")])
    func readsLevelsEvenWhenOnlyOneIsGiven(levels: [Int?], text: String) throws {
        let adventure = try #require(try Listed(name: "PFS2 1-00: A", levels: levels).scenario().adventure)
        #expect((adventure.levelRange?.displayText ?? "") == text)
    }

    @Test func anAnswerWithErrorsFailsWithWarhornsReason() {
        let reply = Data(#"{"errors":[{"message":"Query has complexity of 6505"}]}"#.utf8)
        #expect(throws: ParsingError(operation: WarhornCatalog.operation, reason: "Query has complexity of 6505")) {
            try WarhornPage(reply: reply)
        }
        #expect(throws: ParsingError.self) { try WarhornPage(reply: Data("<html>".utf8)) }
        #expect(throws: ParsingError.self) { try WarhornPage(reply: Data("{}".utf8)) }
    }
}

struct WarhornCatalogTests {
    private let carnival = Listed(name: "PFS2 6-04: An Enkindled Carnival", levels: [3, 6])
    private let submerged = Listed(name: "SFS1 6-04: Secrets Long Submerged", campaign: "SFS1", levels: [9, 12])

    @Test(arguments: [
        ("6-04", ["PFS2 6-04", "SFS1 6-04"]),
        (" #6–0 ", ["PFS2 6-0", "SFS1 6-0"]),
        ("10-", ["PFS2 10-", "SFS1 10-"]),
        ("Carnival", ["Carnival"]),
        ("Quest #14", ["Quest #14"]),
        ("ca", []),
        ("", [])
    ])
    func asksForANumberUnderEachCampaignsCode(typed: String, asked: [String]) {
        #expect(WarhornCatalog.searchTexts(for: typed, campaigns: [.pathfinder2, .starfinder1]) == asked)
    }

    @Test func findsANumberInEveryCampaign() async throws {
        let stub = WarhornStub()
        stub.answer("PFS2 6-04", pages: [[carnival, Listed(name: "PFS2 6-04 at our store", isCustom: true)]])
        stub.answer("SFS1 6-04", pages: [[submerged]])
        let found = try await WarhornCatalog(http: stub)
            .adventures(matching: "6-04", in: [.starfinder1, .pathfinder2, .other("Homebrew")])
        #expect(found.adventures.map(\.title) == ["#6-04: An Enkindled Carnival", "#6-04: Secrets Long Submerged"])
        #expect(found.isComplete)
        #expect(Set(stub.questions.map(\.text)) == ["PFS2 6-04", "SFS1 6-04"])
    }

    @Test func sendsAGraphQLQueryForAHundredScenarios() async throws {
        let stub = WarhornStub()
        _ = try await WarhornCatalog(http: stub).adventures(matching: "Carnival", in: [.pathfinder2])
        let request = try #require(stub.requests.first)
        let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(request.url?.absoluteString == "https://warhorn.net/graphql")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect((body["query"] as? String)?.contains("globalScenarios(query: $query") == true)
        #expect((body["variables"] as? [String: Any])?["first"] as? Int == 100)
    }

    @Test func readsEveryPageAndKeepsOnlyTheChosenCampaigns() async throws {
        let stub = WarhornStub()
        stub.answer("Carnival", pages: [
            [Listed(name: "Carnival of Tears", campaign: "DDAL")], [carnival, carnival],
            [Listed(name: "SFS1 2-02: Carnival Station", campaign: "SFS1")]
        ])
        let found = try await WarhornCatalog(http: stub).adventures(matching: "Carnival", in: [.pathfinder2])
        #expect(found.adventures.map(\.title) == ["#6-04: An Enkindled Carnival"])
        #expect(found.isComplete)
        #expect(stub.questions.map(\.after) == [nil, "1", "2"])
    }

    @Test func stopsReadingACommonWordAndSaysThereIsMore() async throws {
        let stub = WarhornStub()
        stub.isEndless = true
        stub.answer("the", pages: [[carnival]])
        let found = try await WarhornCatalog(http: stub).adventures(matching: "the", in: [.pathfinder2])
        #expect(!found.isComplete)
        #expect(found.adventures.count == 1)
        #expect(stub.questions.count == WarhornCatalog.longestSearch)
    }

    @Test func asksNothingForTooLittleTextOrOtherCampaigns() async throws {
        let stub = WarhornStub()
        let catalog = WarhornCatalog(http: stub)
        #expect(try await catalog.adventures(matching: "ca", in: [.pathfinder2]) == .none)
        #expect(try await catalog.adventures(matching: "Carnival", in: [.other("Homebrew")]) == .none)
        #expect(try await catalog.adventures(matching: "6-04", in: []) == .none)
        #expect(stub.questions.isEmpty)
    }

    @Test(arguments: [
        (500, "Warhorn answered with HTTP 500"), (429, "Warhorn is asking the app to slow down for a few minutes")
    ])
    func aRefusalFailsWithItsReason(status: Int, reason: String) async {
        let stub = WarhornStub()
        stub.status = status
        await #expect(throws: ParsingError(operation: "Searching Warhorn's catalog", reason: reason)) {
            try await WarhornCatalog(http: stub).adventures(matching: "Carnival", in: [.pathfinder2])
        }
    }

    @Test func saysWhyThePublishedAdventuresAreMissing() {
        let offline = AdventureSearchFailure.text(for: URLError(.notConnectedToInternet))
        let refused = AdventureSearchFailure.text(
            for: ParsingError(operation: WarhornCatalog.operation, reason: "Warhorn answered with HTTP 500"))
        #expect(offline == "You are not connected to the internet, so only your own adventures are listed.")
        #expect(refused == "The published adventures couldn't be searched (Warhorn answered with HTTP 500), "
            + "so only your own are listed.")
        #expect(AdventureSearchFailure.text(for: URLError(.timedOut)).contains("couldn't be searched"))
    }
}

struct DemoAdventureSearchTests {
    @Test func theDemoSearchesItsOwnAdventuresOffline() async throws {
        let search = DemoAdventureSearch()
        let clockmaker = try await search.adventures(matching: "clockmaker", in: [.pathfinder2, .starfinder2])
        let starfinder = try await search.adventures(matching: "1-0", in: [.starfinder2])
        #expect(clockmaker.adventures.map(\.title) == ["#6-14: The Clockmaker's Debt"])
        #expect(clockmaker.isComplete)
        #expect(starfinder.adventures.map(\.code) == ["1-03", "1-09"])
        #expect(try await search.adventures(matching: " ", in: [.pathfinder2]) == .none)
    }

    @Test func theDemosCharactersHavePlayedSomeOfThemButNotAll() throws {
        let played = DemoAccount.snapshot().sessions
        let entries = DemoAdventureSearch.published.map(AdventureEntry.init(published:))
        #expect(entries.contains { entry in played.contains(where: entry.matches) })
        #expect(entries.contains { entry in !played.contains(where: entry.matches) })
        #expect(entries.contains { $0.isRepeatable })
    }
}
