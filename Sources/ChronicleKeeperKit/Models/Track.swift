import Foundation

/// The advancement speed a character used for a session.
public enum Track: String, Hashable, Codable, Sendable, CaseIterable {
    case normal
    case slow

    /// The share of the normal rewards this track earns.
    public var rewardFactor: Double { self == .slow ? 0.5 : 1 }

    public var displayName: String { self == .slow ? "Slow" : "Normal" }
}

/// Where a session's track came from, so the app can say why.
public enum TrackSource: String, Hashable, Codable, Sendable {
    /// The user chose it for this session.
    case override
    /// Worked out from the reputation the session earned.
    case inferred
    /// The campaign didn't allow slow track yet.
    case campaignRule
    /// Nothing told us, so the character's default applies.
    case characterDefault
}
