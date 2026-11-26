import Foundation

/// What sort of adventure a session was, which decides its normal XP.
public enum AdventureKind: String, Hashable, Codable, Sendable, CaseIterable {
    case scenario
    case questSeries1
    case questSeries2
    case bounty
    case adventure
    case other

    public var displayName: String {
        switch self {
        case .scenario: "Scenario"
        case .questSeries1, .questSeries2: "Quest"
        case .bounty: "Bounty"
        case .adventure: "Adventure"
        case .other: "Other"
        }
    }

    /// Bounties can be replayed for credit; other adventures normally cannot.
    public var isRepeatable: Bool { self == .bounty }
}

/// The character levels an adventure is designed for.
public struct LevelRange: Hashable, Codable, Sendable {
    public let lowest: Int
    public let highest: Int

    public init(lowest: Int, highest: Int) {
        self.lowest = min(lowest, highest)
        self.highest = max(lowest, highest)
    }

    public func contains(_ level: Int) -> Bool {
        (lowest...highest).contains(level)
    }

    public var displayText: String {
        lowest == highest ? "Level \(lowest)" : "Levels \(lowest)–\(highest)"
    }

    /// The levels worded as a product description words them, so `AdventureClassifier.levelRange` reads them back:
    /// the description of an adventure the app knows only from a catalog.
    public var summaryText: String {
        lowest == highest ? "Designed for level \(lowest)" : "Designed for levels \(lowest)–\(highest)"
    }

    /// The bare numbers, for after a title: "3–7", or "1" for a single level.
    public var shortText: String {
        lowest == highest ? "\(lowest)" : "\(lowest)–\(highest)"
    }
}
