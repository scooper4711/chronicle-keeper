import Foundation

/// Works out what kind of adventure a session was and which levels it is for, from its title and the
/// product description the session links to.
public enum AdventureClassifier {
    /// A title that numbers a quest outranks the description, which calls some quests scenarios.
    public static func kind(of adventure: AdventureReference) -> AdventureKind {
        if adventure.title.firstMatch(of: questPattern) != nil { return questKind(adventure.title) }
        return kindFromSummary(adventure) ?? kindFromTitle(adventure.title)
    }

    /// The kind of an adventure a catalog names, which has no description to go by: its number says what it is.
    /// Only a numbered quest counts as one, so that "The Ranger's Request" and "Quest for the Frozen Flame" don't.
    public static func kind(ofPublished title: String) -> AdventureKind {
        if title.firstMatch(of: questPattern) != nil { return questKind(title) }
        if title.firstMatch(of: bountyPattern) != nil { return .bounty }
        if title.firstMatch(of: seasonPattern) != nil || title.hasPrefix("Intro") { return .scenario }
        return title.firstMatch(of: longAdventurePattern) == nil ? .other : .adventure
    }

    /// The level range from a description such as "designed for 1st- through 4th-level characters", "designed for
    /// levels 1–4 (subtiers 1–2 and 3–4)", "for 5th-6th level characters" or "designed for 5th to 9th level
    /// characters (Tiers: 5–6 and 8–9)": Paizo has worded it many ways over the years.
    public static func levelRange(of adventure: AdventureReference) -> LevelRange? {
        let text = adventure.summary.replacingOccurrences(of: "–", with: "-")
        for pattern in [ordinalRangePattern, levelsPattern] {
            if let match = text.firstMatch(of: pattern) {
                return LevelRange(lowest: Int(match.1) ?? 1, highest: Int(match.2) ?? 1)
            }
        }
        for pattern in [ordinalLevelPattern, singleLevelPattern] {
            if let match = text.firstMatch(of: pattern) {
                let level = Int(match.1) ?? 1
                return LevelRange(lowest: level, highest: level)
            }
        }
        return nil
    }

    /// A short code that identifies an adventure across title spellings: "6-04", "Quest 14", "Bounty 19".
    public static func code(of adventure: AdventureReference) -> String? {
        code(inText: adventure.title)
    }

    /// The code in any text that names an adventure, such as the title line of its chronicle sheet: "Pathfinder
    /// Society Scenario #1–00:", "Scenario # 2-13", "Quest #22", "Bounty #19:" or "Pathfinder Society 8-01: Intro
    /// to the Year…", which has no "#". The same adventure gets the same code from its session and from its sheet.
    public static func code(inText text: String) -> String? {
        let plain = text.replacing(/[–—]/, with: "-").replacing(/#\s+/, with: "#")
        if let match = plain.firstMatch(of: seasonPattern) { return "\(match.1)-\(match.2)" }
        if let match = plain.firstMatch(of: questPattern) { return "Quest \(match.1)" }
        if let match = plain.firstMatch(of: bountyPattern) { return "Bounty \(match.1)" }
        if let match = plain.firstMatch(of: unmarkedSeasonPattern) { return "\(match.1)-\(match.2)" }
        return nil
    }

    /// The code in what the user typed as a scenario number: "6-04", "#6-4", "quest 14" or "Bounty #19", and
    /// anything `code(inText:)` reads. A scenario's number gets its two digits, as paizo.com writes it.
    public static func code(typed text: String) -> String? {
        let plain = text.trimmingCharacters(in: .whitespaces).replacing(/[–—]/, with: "-")
        if let match = plain.wholeMatch(of: typedSeasonPattern), let number = Int(match.2) {
            return "\(match.1)-" + (number < 10 ? "0\(number)" : "\(number)")
        }
        if let match = plain.wholeMatch(of: typedSeriesPattern) {
            return "\(match.1.capitalized) \(match.2)"
        }
        return code(inText: plain)
    }

    /// A title that carries a code and nothing else, for an adventure known only by its number: "#6-04",
    /// "Quest #14", "Bounty #19". `code(of:)` and `kind(of:)` read it like paizo.com's own titles.
    public static func title(forCode code: String) -> String {
        if code.wholeMatch(of: typedSeasonPattern) != nil { return "#\(code)" }
        guard let match = code.wholeMatch(of: typedSeriesPattern) else { return code }
        return "\(match.1.capitalized) #\(match.2)"
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
    /// "1st- through 4th-level", "5th to 9th level", "5th-6th level".
    nonisolated(unsafe) private static let ordinalRangePattern =
        /(\d+)(?:st|nd|rd|th)-?(?: through | to )?(\d+)(?:st|nd|rd|th)[- ]level/
    /// "levels 1-4", "Levels 7-11", "level 1-2".
    nonisolated(unsafe) private static let levelsPattern = /[Ll]evels? (\d+)\s*-\s*(\d+)/
    /// "for 3rd-level characters", "for 12th level characters".
    nonisolated(unsafe) private static let ordinalLevelPattern = /for (\d+)(?:st|nd|rd|th)[- ]level/
    /// "designed for level 1".
    nonisolated(unsafe) private static let singleLevelPattern = /for level (\d+)/
    nonisolated(unsafe) private static let seasonPattern = /#(\d+)-(\d+)/
    /// A season and number with no "#", as season 8's sheets print it: "Pathfinder Society 8-01:".
    nonisolated(unsafe) private static let unmarkedSeasonPattern = /Society (\d+)-(\d+):/
    /// "Quest #3" or "Quest (Series 2) #14", and not a scenario with "Quest" in its name, such as "#3-09: The Quest
    /// for Perfection—Part I - [Some Con] PFS #3-09: …", whose later "#3" would otherwise read as the quest's number.
    nonisolated(unsafe) static let questPattern = /Quest(?: \(Series \d+\))? #(\d+)/
    nonisolated(unsafe) private static let bountyPattern = /Bounty #(\d+)/
    /// "6-04" or "#6-4", alone.
    nonisolated(unsafe) private static let typedSeasonPattern = /#?\s*(\d+)\s*-\s*(\d+)/
    /// "Quest 14" or "bounty #19", alone.
    nonisolated(unsafe) private static let typedSeriesPattern = /(?i)(quest|bounty)\s*#?\s*(\d+)/
    /// How Warhorn starts the name of a standalone adventure, an Adventure Path volume and a first edition module.
    nonisolated(unsafe) private static let longAdventurePattern = /^(?:Adventure|AP|Mod)\b/
}
