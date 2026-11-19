import Foundation

/// The demo's stand-in for Warhorn's catalog: a few made-up published adventures, searched without the network.
public struct DemoAdventureSearch: AdventureSearching {
    public init() {}

    public func adventures(matching text: String, in campaigns: [Campaign]) async throws -> AdventureSearchResults {
        let needle = text.trimmingCharacters(in: .whitespaces)
        let matches = Self.published.filter { adventure in
            campaigns.contains(adventure.campaign) && adventure.title.localizedCaseInsensitiveContains(needle)
        }
        return AdventureSearchResults(adventures: matches.map(AdventureEntry.init(published:)), isComplete: true)
    }

    /// Some the demo's characters have played, under the titles their sessions use, and some nobody has.
    static let published: [PublishedAdventure] = [
        adventure("#6-02: The Lantern Fair", levels: 1...4),
        adventure("#6-09: Tides of the Glass Sea", levels: 3...6),
        adventure("#6-14: The Clockmaker's Debt", levels: 1...4),
        adventure("#6-17: Embers over Brightwater", levels: 5...8),
        adventure("Bounty #22: The Ferryman's Wager", levels: 1...1, isRepeatable: true),
        adventure("#1-03: Static on the Drift", levels: 1...4, campaign: .starfinder2),
        adventure("#1-09: A Signal from Nowhere", levels: 3...6, campaign: .starfinder2)
    ]

    private static func adventure(
        _ title: String, levels: ClosedRange<Int>, campaign: Campaign = .pathfinder2, isRepeatable: Bool = false
    ) -> PublishedAdventure {
        var adventure = PublishedAdventure(campaign: campaign, title: title)
        adventure.levelRange = LevelRange(lowest: levels.lowerBound, highest: levels.upperBound)
        adventure.isRepeatable = isRepeatable
        return adventure
    }
}
