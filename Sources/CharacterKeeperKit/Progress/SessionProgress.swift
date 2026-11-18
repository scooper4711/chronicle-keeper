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
