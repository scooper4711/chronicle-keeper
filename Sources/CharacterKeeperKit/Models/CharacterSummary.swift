import Foundation

/// A name and a number, such as "Horizon Hunters: 68" or "Fame: 89".
public struct NamedValue: Hashable, Codable, Sendable {
    public let name: String
    public let value: Int

    public init(name: String, value: Int) {
        self.name = name
        self.value = value
    }
}

/// One row of the Summary tab: a character and the standing Paizo has recorded for it.
public struct CharacterSummary: Hashable, Codable, Sendable, Identifiable {
    /// The full Organized Play number, such as "123456-2001".
    public let number: String
    public let campaign: Campaign
    public let name: String
    /// Reputation per faction, in the site's order.
    public let factions: [NamedValue]
    /// Campaign-wide totals the site shows after the factions: Fame, Total Reputation or Prestige.
    public let standing: [NamedValue]

    public var id: String { number }

    public init(number: String, campaign: Campaign, name: String, factions: [NamedValue], standing: [NamedValue]) {
        self.number = number
        self.campaign = campaign
        self.name = name
        self.factions = factions
        self.standing = standing
    }
}
