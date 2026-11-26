import Foundation

/// A free reward the Boons tab offers every player of a campaign: a row of one of its "Rewards purchaseable with …"
/// lists. Whether a character may claim it is `RewardEligibility`'s to say.
public struct RewardOffer: Hashable, Codable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Codable, Sendable {
        /// Free once the character has played the adventure.
        case chronicleBoon
        /// Free once the character meets a condition, such as a reputation.
        case gameReward
    }

    public let kind: Kind
    public let campaign: Campaign
    /// As the list names it, which is also how "Boons you have purchased" names it once claimed.
    public let name: String
    /// The list's description, which ends with the condition where there is one.
    public let summary: String

    public var id: String { "\(campaign.shortName)|\(kind.rawValue)|\(name)" }

    public init(type: RewardPointType, name: String, summary: String) {
        kind = type.kind
        campaign = type.campaign
        self.name = name
        self.summary = summary
    }
}

/// What a list's rewards cost, as the Boons tab words it: "Chronicle Boons - PFS(2ed)" or "Game Rewards - SFS".
/// Every reward of these two kinds costs nothing; the other point types (Achievement Points, Playtest Points) are
/// spent, and the app leaves their lists alone.
public struct RewardPointType: Hashable, Sendable {
    public let kind: RewardOffer.Kind
    public let campaign: Campaign

    /// Nil for a point type whose rewards aren't free, and for a campaign the app doesn't know.
    public init?(_ text: String) {
        let parts = text.split(separator: " - ", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let kind = Self.kinds[parts[0]] else { return nil }
        let campaign = Campaign(code: parts[1])
        if case .other = campaign { return nil }
        self.kind = kind
        self.campaign = campaign
    }

    private static let kinds: [String: RewardOffer.Kind] = [
        "Chronicle Boons": .chronicleBoon, "Game Rewards": .gameReward
    ]
}

/// The free reward lists, and when they were read. They are the same for every player, so the saved copy is read
/// again only when it has grown old.
public struct RewardCatalog: Hashable, Codable, Sendable {
    public let offers: [RewardOffer]
    public let fetchedAt: Date

    public init(offers: [RewardOffer], fetchedAt: Date) {
        self.offers = offers
        self.fetchedAt = fetchedAt
    }

    /// Whether the lists should be read again: after 30 days, or after a day when the last reading found none, which
    /// is either an account without these campaigns or a page the app no longer understands.
    public func isStale(at now: Date) -> Bool {
        now.timeIntervalSince(fetchedAt) > (offers.isEmpty ? Self.day : 30 * Self.day)
    }

    private static let day: TimeInterval = 24 * 60 * 60
}

/// Where the reward lists come from: paizo.com, or the demo account.
public protocol RewardCatalogSource: Sendable {
    func rewardCatalog() async throws -> RewardCatalog
}
