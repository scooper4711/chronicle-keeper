import Foundation

/// Where a session's XP came from.
public enum XPSource: String, Hashable, Codable, Sendable {
    /// The Guide's value for the adventure's kind.
    case rules
    /// Worked out from the Achievement Points, because the kind didn't fix it.
    case estimated
    /// The user entered it.
    case override
}

/// What a session contributed to a character: its kind, track and XP, with where each came from.
public struct SessionProgress: Hashable, Sendable, Identifiable {
    public let session: PlayedSession
    public let kind: AdventureKind
    public let track: Track
    public let trackSource: TrackSource
    public let xp: Double
    public let xpSource: XPSource
    /// The character's level at the start of the session: their starting level plus the XP of every earlier session,
    /// each on its own track.
    public internal(set) var levelWhenPlayed = 1
    /// Whether that level was outside the adventure's level range. A Chronicle applied later than it was earned
    /// (a pregen, or a held Chronicle credited once the character catches up) can do this; see "Applying Credit"
    /// in the Guide to Organized Play. The level is still shown, marked, rather than hidden.
    public internal(set) var isOutOfLevelRange = false
    /// The level the credit is treated as applied at: `levelWhenPlayed`, or, when that falls outside the
    /// adventure's level range, the nearest level inside it. A held Chronicle isn't applied until the character
    /// reaches the pregen's level (Applying Credit), and this is our best stand-in for that level without
    /// Paizo's own record of when each held Chronicle was actually applied.
    public internal(set) var creditLevel = 1
    /// XP this session would have given that didn't count, because the character's level was already at, or
    /// would have risen past, this adventure's own highest level: "a character's level cannot exceed the level
    /// of any Chronicle applied to them" (Applying Credit). 0 when nothing was lost.
    public internal(set) var xpLost = 0.0
    /// The character's total banked XP through and including this session (after any loss above is subtracted).
    public internal(set) var totalXP = 0.0

    public var id: String { session.id }
}

/// The user's corrections for one session.
public struct SessionOverride: Hashable, Codable, Sendable {
    public var track: Track?
    public var xp: Double?

    public init(track: Track? = nil, xp: Double? = nil) {
        self.track = track
        self.xp = xp
    }
}
