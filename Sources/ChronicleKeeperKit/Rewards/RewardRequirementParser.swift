import Foundation

/// Reads what a free reward asks for from its name and description, as the Boons tab words them. The wordings are
/// the ones in the lists of 26 November 2026 (the test fixture `reward-conditions.txt`). Whatever else it meets is
/// `.unknown`: a missed reward is better than a false one.
public enum RewardRequirementParser {
    public static func requirement(of offer: RewardOffer) -> RewardRequirement {
        let text = RewardName.plain(offer.summary)
        if let reputation = reputation(in: text, campaign: offer.campaign) { return reputation }
        if let match = text.firstMatch(of: sessionsPattern), let count = Int(match.1) { return .sessions(count) }
        if let match = text.firstMatch(of: playedPattern) { return played(String(match.1), name: offer.name) }
        // Another condition, or a Game Reward that states none: only a Chronicle Boon is named after its adventure.
        if text.firstMatch(of: otherConditionPattern) != nil || offer.kind == .gameReward { return .unknown }
        return .played([adventure(named: offer.name)], needsAll: false)
    }

    // MARK: - Reputation

    /// "Must be Liked by Envoy's Alliance", "Character must be Revered by any Faction", "Must have at least 5
    /// Reputation with the Acquisitives", "Must have 15 or more Reputation with the Dataphiles".
    private static func reputation(in text: String, campaign: Campaign) -> RewardRequirement? {
        if let match = text.firstMatch(of: statusPattern) {
            let ladder = CampaignRules(campaign: campaign).reputationLadder
            guard let points = ladder.threshold(of: String(match.1)) else { return .unknown }
            return .reputation(points: points, faction: faction(String(match.2)))
        }
        if let match = text.firstMatch(of: pointsPattern), let points = Int(match.1) {
            return .reputation(points: points, faction: faction(String(match.2)))
        }
        return nil
    }

    private static func faction(_ name: String) -> String {
        name.caseInsensitiveCompare("any Faction") == .orderedSame ? "" : name
    }

    // MARK: - Adventures played

    /// What follows "Must have played", up to "to download".
    private static func played(_ clause: String, name: String) -> RewardRequirement {
        if let match = clause.firstMatch(of: anyPartPattern) {
            // "at least one volume of Strength of Thousands": any session whose title names the series.
            return .played([RewardAdventure(titles: [String(match.1)])], needsAll: false)
        }
        // "all three scenarios in the Fleeting Truth series with the same character" can't be checked.
        guard clause.firstMatch(of: everyPartPattern) == nil else { return .unknown }
        // "Ruins of Gauntlight or part 1 of the Abomination Vaults Compilation": the volume can be checked, the
        // compilation can't, so only the volume counts.
        let checkable = clause.replacing(compilationPattern, with: "")
        let either = checkable.split(separator: " OR ").map(String.init)
        let each = checkable.split(separator: " AND ").map(String.init)
        guard either.count == 1 || each.count == 1 else { return .unknown }
        let parts = each.count > 1 ? each : either
        // "#4-03: Stalwart Shield … Must have played Linnorm's Legacy": the name's own number says which adventure.
        let nameCode = parts.count == 1 ? code(in: RewardName.plain(name)) : ""
        let adventures = parts.map { part in
            let own = code(in: part)
            return RewardAdventure(code: own.isEmpty ? nameCode : own, titles: titles(in: part))
        }
        return .played(adventures, needsAll: each.count > 1)
    }

    /// A Chronicle Boon that states no condition is named after its adventure: "PFS (2ed) Scenario #1–03: Escaping
    /// the Grave", "Pathfinder Module: The Fall of Plaguestone Boon A".
    private static func adventure(named name: String) -> RewardAdventure {
        let title = RewardName.withoutLetter(name)
        return RewardAdventure(code: code(in: title), titles: [title])
    }

    /// The spellings to try: a quoted title alone (`"The Blade's Legacy" from the Kingmaker Companion Guide`), or the
    /// text with and without its parentheses ("The Choosing (Stolen Fate #1)").
    private static func titles(in part: String) -> [String] {
        if let match = part.firstMatch(of: quotedPattern) { return [String(match.1)] }
        let whole = part.trimmingCharacters(in: .whitespaces)
        let bare = whole.replacing(parenthesisPattern, with: "").trimmingCharacters(in: .whitespaces)
        return bare.isEmpty || bare == whole ? [whole] : [whole, bare]
    }

    /// "6-03", "Quest 2" or "Bounty 19" as `AdventureClassifier.code` writes them, or an empty string. The lists
    /// write a scenario's number with and without its "#".
    static func code(in text: String) -> String {
        if let match = text.firstMatch(of: seasonPattern) { return "\(match.1)-\(match.2)" }
        if let match = text.firstMatch(of: AdventureClassifier.questPattern) { return "Quest \(match.1)" }
        if let match = text.firstMatch(of: bountyPattern) { return "Bounty \(match.1)" }
        return ""
    }

    // MARK: - Patterns

    // Regex is not Sendable, but these literals are never mutated, so sharing them is safe.

    nonisolated(unsafe) private static let statusPattern =
        /[Mm]ust be (\w+) by (.+?) to (?:obtain|purchase|download)/
    nonisolated(unsafe) private static let pointsPattern =
        /[Mm]ust have (?:at least )?(\d+)(?: or more)? Reputation with (?:the )?(.+?) to (?:obtain|purchase|download)/
    nonisolated(unsafe) private static let sessionsPattern = /[Mm]ust have played (\d+) sessions/
    nonisolated(unsafe) private static let playedPattern =
        /[Mm]ust have (?:played|credit for) (.+?) to (?:obtain|purchase|download)/
    nonisolated(unsafe) private static let otherConditionPattern = /[Mm]ust (?:have|be|complete)|May be downloaded/
    nonisolated(unsafe) private static let anyPartPattern =
        /^at least one (?:level|volume|part|scenario) (?:of|in) (?:the )?(.+?)(?: series| Adventure Path)?$/
    nonisolated(unsafe) private static let everyPartPattern = /^all\b/
    nonisolated(unsafe) private static let compilationPattern = /\ or [Pp]art \d+ of the .+$/
    nonisolated(unsafe) private static let quotedPattern = /^\s*"([^"]+)"/
    nonisolated(unsafe) private static let parenthesisPattern = /\s*\([^)]*\)/
    /// A season and a two-digit scenario, "#6-03" or "1-10", that isn't the tail of a word ("Locus-1").
    nonisolated(unsafe) private static let seasonPattern = /(?:^|[^\w-])#?(\d{1,2})-(\d{2})(?!\d)/
    nonisolated(unsafe) private static let bountyPattern = /Bounty #(\d+)/
}
