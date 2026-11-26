import Foundation

/// The statuses a faction's reputation passes through in one campaign, and the reputation each begins at, from the
/// Guide to Organized Play on lorespire.paizo.com.
public struct ReputationLadder: Hashable, Sendable {
    public struct Step: Hashable, Sendable {
        public let name: String
        /// The reputation the status begins at.
        public let threshold: Int

        public init(name: String, threshold: Int) {
            self.name = name
            self.threshold = threshold
        }
    }

    /// Lowest first. Empty for a campaign whose factions have no statuses.
    public let steps: [Step]

    public init(steps: [Step]) {
        self.steps = steps.sorted { $0.threshold < $1.threshold }
    }

    public var isEmpty: Bool { steps.isEmpty }

    /// The status that much reputation has reached, or an empty string when the campaign has none.
    public func status(for reputation: Int) -> String {
        steps.last { $0.threshold <= reputation }?.name ?? ""
    }

    /// The first status that much reputation hasn't reached, or nil at the top of the ladder.
    public func nextStep(after reputation: Int) -> Step? {
        steps.first { $0.threshold > reputation }
    }

    /// "12 more to Admired", or an empty string at the top of the ladder and when the campaign has none.
    public func distanceToNextStatus(from reputation: Int) -> String {
        guard let next = nextStep(after: reputation) else { return "" }
        return "\(next.threshold - reputation) more to \(next.name)"
    }

    /// The reputation a status begins at, as in "Must be Liked by Envoy's Alliance": 20. Nil for a name the ladder
    /// doesn't have.
    public func threshold(of status: String) -> Int? {
        steps.first { $0.name.caseInsensitiveCompare(status) == .orderedSame }?.threshold
    }
}

extension ReputationLadder {
    /// A campaign without statuses: first edition Pathfinder Society counts Fame and Prestige instead, and second
    /// edition Starfinder Society has no factions.
    public static let none = ReputationLadder(steps: [])

    /// Pathfinder Society (second edition), "Factions and Reputation", table "Reputations": Ignored 0–19, Liked
    /// 20–59, Admired 60–119, Revered 120+. "Reputation in PFS does not use negative values."
    public static let pathfinder2 = ReputationLadder(steps: [
        Step(name: "Ignored", threshold: 0), Step(name: "Liked", threshold: 20),
        Step(name: "Admired", threshold: 60), Step(name: "Revered", threshold: 120)
    ])

    /// Starfinder Society (first edition), "Reputation Tiers", table "Reputation Tier Thresholds": tier 0 at 0+, 1 at
    /// 5+, 2 at 15+, 3 at 25+, 4 at 45+.
    public static let starfinder1 = ReputationLadder(steps: [
        Step(name: "Tier 0", threshold: 0), Step(name: "Tier 1", threshold: 5), Step(name: "Tier 2", threshold: 15),
        Step(name: "Tier 3", threshold: 25), Step(name: "Tier 4", threshold: 45)
    ])
}

extension CampaignRules {
    /// The statuses a faction's reputation earns in this campaign.
    public var reputationLadder: ReputationLadder {
        switch campaign {
        case .pathfinder2: .pathfinder2
        case .starfinder1: .starfinder1
        case .pathfinder1, .starfinder2, .other: .none
        }
    }
}
