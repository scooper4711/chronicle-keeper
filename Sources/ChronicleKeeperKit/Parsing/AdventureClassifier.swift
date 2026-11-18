import Foundation

/// Works out what kind of adventure a session was and which levels it is for, from its title and the
/// product description the session links to.
public enum AdventureClassifier {
    public static func kind(of adventure: AdventureReference) -> AdventureKind {
        kindFromSummary(adventure) ?? kindFromTitle(adventure.title)
    }

    /// The level range from a description such as "designed for 1st- through 4th-level characters" or
    /// "designed for levels 1–4 (subtiers 1–2 and 3–4)".
    public static func levelRange(of adventure: AdventureReference) -> LevelRange? {
        let text = adventure.summary.replacingOccurrences(of: "–", with: "-")
        if let match = text.firstMatch(of: throughPattern) {
            return LevelRange(lowest: Int(match.1) ?? 1, highest: Int(match.2) ?? 1)
        }
        if let match = text.firstMatch(of: levelsPattern) {
            return LevelRange(lowest: Int(match.1) ?? 1, highest: Int(match.2) ?? 1)
        }
        if let match = text.firstMatch(of: singleLevelPattern) {
            let level = Int(match.1) ?? 1
            return LevelRange(lowest: level, highest: level)
        }
        return nil
    }

    /// A short code that identifies an adventure across title spellings: "6-04", "Quest 14", "Bounty 19".
    public static func code(of adventure: AdventureReference) -> String? {
        let title = adventure.title
        if let match = title.firstMatch(of: seasonPattern) { return "\(match.1)-\(match.2)" }
        if let match = title.firstMatch(of: questPattern) { return "Quest \(match.1)" }
        if let match = title.firstMatch(of: bountyPattern) { return "Bounty \(match.1)" }
        return nil
    }

    // MARK: - Kind

    private static func kindFromSummary(_ adventure: AdventureReference) -> AdventureKind? {
        guard let match = adventure.summary.firstMatch(of: summaryKindPattern) else { return nil }
        switch match.1.lowercased() {
        case "scenario", "special": return .scenario
        case "quest": return questKind(adventure.title)
        case "bounty": return .bounty
        default: return .adventure
        }
    }

    private static func kindFromTitle(_ title: String) -> AdventureKind {
        let lowered = title.lowercased()
        if lowered.contains("bounty") { return .bounty }
        if lowered.contains("quest") { return questKind(title) }
        if title.firstMatch(of: seasonPattern) != nil || lowered.hasPrefix("intro") { return .scenario }
        if lowered.contains("adventure path") { return .adventure }
        return .other
    }

    /// Series 2 quests are the "(Series 2)" ones, numbered 14 and up.
    private static func questKind(_ title: String) -> AdventureKind {
        if title.contains("Series 2") { return .questSeries2 }
        let number = title.firstMatch(of: questPattern).flatMap { Int($0.1) } ?? 0
        return number >= 14 ? .questSeries2 : .questSeries1
    }

    // MARK: - Patterns

    // Regex is not Sendable, but these literals are never mutated, so sharing them is safe.

    nonisolated(unsafe) private static let summaryKindPattern =
        /^An? (?:Pathfinder|Starfinder)(?: Society)? (Scenario|Special|Quest|Bounty|Adventure)\b/
    nonisolated(unsafe) private static let throughPattern = /(\d+)(?:st|nd|rd|th)-? through (\d+)(?:st|nd|rd|th)-level/
    nonisolated(unsafe) private static let levelsPattern = /levels (\d+)\s*-\s*(\d+)/
    nonisolated(unsafe) private static let singleLevelPattern = /designed for (\d+)(?:st|nd|rd|th)-level/
    nonisolated(unsafe) private static let seasonPattern = /#(\d+)-(\d+)/
    nonisolated(unsafe) private static let questPattern = /Quest[^#]*#(\d+)/
    nonisolated(unsafe) private static let bountyPattern = /Bounty #(\d+)/
}
