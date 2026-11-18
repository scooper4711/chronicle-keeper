import Foundation

/// Whether a character can play an adventure, and if not, why.
public enum Eligibility: Hashable, Sendable {
    case eligible
    case alreadyPlayed(Date?)
    case outsideLevels(level: Int, range: LevelRange)

    public var isEligible: Bool { self == .eligible }
}

public struct Candidate: Hashable, Sendable, Identifiable {
    public let character: CharacterRecord
    public let eligibility: Eligibility

    public var id: String { character.id }
}

/// "Who can play X?": the characters in the adventure's campaign, those who can play it first.
public enum AdventureFinder {
    public static func candidates(for adventure: AdventureEntry, in roster: CharacterRoster) -> [Candidate] {
        roster.characters(in: adventure.campaign)
            .map { Candidate(character: $0, eligibility: eligibility(of: $0, for: adventure)) }
            .sorted(by: isBefore)
    }

    public static func eligibility(of character: CharacterRecord, for adventure: AdventureEntry) -> Eligibility {
        if !adventure.isRepeatable, let played = character.sessions.first(where: { adventure.matches($0.session) }) {
            return .alreadyPlayed(played.session.date)
        }
        if let range = adventure.levelRange, !range.contains(character.level.level) {
            return .outsideLevels(level: character.level.level, range: range)
        }
        return .eligible
    }

    /// Eligible characters first, then by level, then by name.
    private static func isBefore(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.eligibility.isEligible != rhs.eligibility.isEligible { return lhs.eligibility.isEligible }
        if lhs.character.level.level != rhs.character.level.level {
            return lhs.character.level.level < rhs.character.level.level
        }
        return lhs.character.name < rhs.character.name
    }
}
