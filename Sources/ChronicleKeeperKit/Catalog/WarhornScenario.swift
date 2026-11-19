import Foundation

/// A scenario as Warhorn's catalog lists it. Warhorn serves every game and lets each event add entries of its own,
/// so only some scenarios are adventures Paizo published for Organized Play.
struct WarhornScenario: Decodable, Sendable {
    struct CampaignCode: Decodable, Sendable {
        let code: String?
    }

    struct Tag: Decodable, Sendable {
        let name: String
    }

    let name: String
    let minLevel: Int?
    let maxLevel: Int?
    let isCustom: Bool
    let coverArtUrl: String?
    let campaign: CampaignCode?
    let tags: [Tag]

    /// The four Organized Play campaigns, by the codes Warhorn gives them.
    static let campaigns: [String: Campaign] = [
        "PFS1": .pathfinder1, "PFS2": .pathfinder2, "SFS1": .starfinder1, "SFS2": .starfinder2
    ]

    /// The adventure, or nothing for an entry an event made for itself, another game's scenario, or a stand-in such
    /// as "PFS2: Scenario Pending".
    var adventure: PublishedAdventure? {
        guard !isCustom, !isStandIn, let campaign = Self.campaigns[campaign?.code ?? ""] else { return nil }
        var adventure = PublishedAdventure(campaign: campaign, title: Self.title(from: name))
        adventure.levelRange = levelRange
        adventure.isRepeatable = tags.contains { $0.name.caseInsensitiveCompare("Repeatable") == .orderedSame }
        adventure.coverArt = coverArtUrl.flatMap(URL.init(string:)).flatMap { CoverHost.isAllowed($0) ? $0 : nil }
        return adventure
    }

    /// The title the way the Sessions tab mostly spells it: "PFS2 6-04: An Enkindled Carnival" becomes "#6-04: An
    /// Enkindled Carnival", and "PF2 Bounty 10: Hillcross Roundup" becomes "Bounty #10: Hillcross Roundup".
    static func title(from name: String) -> String {
        name.replacing(campaignPattern, with: "")
            .replacing(seasonPattern) { "#\($0.1)" }
            .replacing(numberPattern) { "\($0.1) #\($0.2)" }
    }

    private var isStandIn: Bool {
        name.contains("Scenario Pending") || name.contains("Infinite Scenario")
    }

    private var levelRange: LevelRange? {
        guard let lowest = minLevel ?? maxLevel, lowest > 0 else { return nil }
        return LevelRange(lowest: lowest, highest: maxLevel ?? lowest)
    }

    // Regex is not Sendable, but these literals are never mutated, so sharing them is safe.

    /// "PFS2 ", "SFS1: ", "PF2 ", "SF1 " or "PFS " in front of a name.
    nonisolated(unsafe) private static let campaignPattern = /^[PS]FS?\d?:?\ /
    nonisolated(unsafe) private static let seasonPattern = /^(\d+-\w+)/
    nonisolated(unsafe) private static let numberPattern = /^(Bounty|Intro|Quest|One-Shot) (\d+)/
}

/// One page of a search of Warhorn's catalog.
struct WarhornPage: Sendable {
    let scenarios: [WarhornScenario]
    /// Where the next page starts, or nothing after the last one.
    let nextCursor: String?

    /// Reads the answer to `WarhornQuery`, which is either the scenarios or the reasons there are none.
    init(reply data: Data) throws {
        guard let reply = try? JSONDecoder().decode(WarhornReply.self, from: data) else {
            throw ParsingError(operation: WarhornCatalog.operation, reason: "the answer isn't the one the app expects")
        }
        guard let found = reply.data?.globalScenarios else {
            let reason = reply.errors?.first?.message ?? "the answer has no scenarios"
            throw ParsingError(operation: WarhornCatalog.operation, reason: reason)
        }
        scenarios = found.nodes
        nextCursor = found.pageInfo.hasNextPage ? found.pageInfo.endCursor : nil
    }
}

/// Warhorn's answer: the scenarios, or the reasons there are none.
private struct WarhornReply: Decodable {
    struct Content: Decodable {
        let globalScenarios: WarhornConnection
    }

    struct Failure: Decodable {
        let message: String
    }

    let data: Content?
    let errors: [Failure]?
}

private struct WarhornConnection: Decodable {
    struct PageInfo: Decodable {
        let hasNextPage: Bool
        let endCursor: String?
    }

    let nodes: [WarhornScenario]
    let pageInfo: PageInfo
}

/// The GraphQL request for one page of scenarios whose name contains the text.
struct WarhornQuery: Encodable, Sendable {
    struct Variables: Encodable, Sendable {
        let query: String
        let first: Int
        let after: String?
    }

    let query = WarhornQuery.document
    let variables: Variables

    init(text: String, after cursor: String?) {
        variables = Variables(query: text, first: WarhornCatalog.pageSize, after: cursor)
    }

    static let document = """
        query Adventures($query: String, $first: Int, $after: String) {
          globalScenarios(query: $query, first: $first, after: $after) {
            nodes { name minLevel maxLevel isCustom coverArtUrl campaign { code } tags { name } }
            pageInfo { hasNextPage endCursor }
          }
        }
        """
}
