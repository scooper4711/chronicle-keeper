import ChronicleKeeperKit
import Foundation

/// A session's numbers spelled out, for the adventures table's help tags and the session's details.
enum SessionExplanation {
    /// Why a held Chronicle shows the level it does (R2.6).
    static func heldChronicle(_ progress: SessionProgress) -> String {
        "The character was level \(progress.levelWhenPlayed) when this was played, outside the "
            + "adventure's level range. The Guide to Organized Play holds a Chronicle like this until "
            + "the character reaches the pregen's level, so it's shown credited at \(progress.creditLevel), "
            + "the nearest level in range."
    }

    /// Why some XP didn't count, or that the XP is an estimate; empty when there is nothing to say.
    static func xp(_ progress: SessionProgress) -> String {
        if progress.xpLost > 0 {
            return "\(XPText.of(progress.xpLost)) XP didn't count: the character's level can't pass this "
                + "adventure's own highest level (see the Guide to Organized Play's \"Applying Credit\")."
        }
        switch progress.xpSource {
        case .estimated: return "Estimated from the Achievement Points"
        case .chronicle: return "From the Chronicle Sheet"
        case .rules, .override: return ""
        }
    }
}

/// The lines of a session's details.
enum SessionFactText {
    /// "Scenario · Levels 1–4".
    static func adventure(_ progress: SessionProgress) -> String {
        let kind = progress.kind.displayName
        guard let range = AdventureClassifier.levelRange(of: progress.session.adventure) else { return kind }
        return "\(kind) · \(range.displayText)"
    }

    static func level(_ progress: SessionProgress) -> String {
        progress.isOutOfLevelRange
            ? "Credited at level \(progress.creditLevel), played at level \(progress.levelWhenPlayed)"
            : "Level \(progress.creditLevel) when played"
    }

    /// "4 XP awarded", with what was lost of it.
    static func xp(_ progress: SessionProgress) -> String {
        let awarded = "\(XPText.of(progress.xp)) XP awarded"
        return progress.xpLost > 0 ? "\(awarded), \(XPText.of(progress.xpLost)) lost" : awarded
    }

    /// "10 of 12 XP into level 3".
    static func progress(_ progress: SessionProgress, perLevel: Double) -> String {
        "\(XPText.of(progress.creditProgress)) of \(XPText.of(perLevel)) XP into level \(progress.creditLevel)"
    }

    /// "4 with Envoy's Alliance", or empty when the session gave none.
    static func reputation(_ session: PlayedSession) -> String {
        guard let earned = session.reputation else { return "" }
        return session.faction.isEmpty ? XPText.of(earned) : "\(XPText.of(earned)) with \(session.faction)"
    }

    /// "12 Achievement Points · 1 GM credit".
    static func points(_ points: SessionPoints) -> String {
        let earned = "\(XPText.of(points.achievementPoints)) Achievement Points"
        guard points.gmCredits > 0 else { return earned }
        return "\(earned) · \(XPText.of(points.gmCredits)) GM credit" + (points.gmCredits == 1 ? "" : "s")
    }

    /// "Lantern Fair 2026 · Event 1234, session 3", without the numbers for a session that has no event code, and
    /// "None" for one that has neither.
    static func event(_ session: PlayedSession) -> String {
        let numbers = session.eventCode.isEmpty ? "" : "Event \(session.eventCode), session \(session.sessionNumber)"
        let parts = [session.eventName, numbers].filter { !$0.isEmpty }
        return parts.isEmpty ? "None" : parts.joined(separator: " · ")
    }
}
