import Foundation

/// The advancement rules of a campaign, from Paizo's Guide to Organized Play (see design.md for sources).
public struct CampaignRules: Sendable {
    public let campaign: Campaign

    public init(campaign: Campaign) {
        self.campaign = campaign
    }

    /// XP needed for each level.
    public var xpPerLevel: Double {
        isSecondEdition ? 12 : 3
    }

    public var maximumLevel: Int { 20 }

    /// Starfinder Society (second edition) has no factions; the others do.
    public var hasFactions: Bool { campaign != .starfinder2 }

    /// The XP an adventure of this kind awards on the normal track, when the Guide fixes it.
    public func normalXP(for kind: AdventureKind) -> Double? {
        isSecondEdition ? secondEditionXP(kind) : firstEditionXP(kind)
    }

    /// The reputation an adventure of this kind normally awards. Some scenarios add bonus reputation.
    public func normalReputation(for kind: AdventureKind) -> Double? {
        isSecondEdition ? secondEditionXP(kind) : firstEditionReputation(kind)
    }

    /// Whether a character could choose slow track on this date. A session without a date counts as allowed.
    public func allowsSlowTrack(on date: Date?) -> Bool {
        guard campaign == .starfinder2, let date else { return true }
        return date >= Self.starfinder2SlowTrackStart
    }

    /// Slow track came to Starfinder Society (second edition) with the Guide update of 30 July 2026.
    public static let starfinder2SlowTrackStart: Date = {
        var components = DateComponents(year: 2026, month: 7, day: 30)
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components) ?? .distantPast
    }()

    private var isSecondEdition: Bool {
        switch campaign {
        case .pathfinder2, .starfinder2, .other: true
        case .pathfinder1, .starfinder1: false
        }
    }

    private func secondEditionXP(_ kind: AdventureKind) -> Double? {
        switch kind {
        case .scenario: 4
        case .questSeries1, .bounty: 1
        case .questSeries2: 2
        case .adventure: 12
        case .other: nil
        }
    }

    private func firstEditionXP(_ kind: AdventureKind) -> Double? {
        kind == .scenario ? 1 : nil
    }

    private func firstEditionReputation(_ kind: AdventureKind) -> Double? {
        kind == .scenario ? 2 : nil
    }
}
