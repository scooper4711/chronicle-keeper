import Foundation

/// A boon the player has bought or earned, as the Boons tab lists it, with the link to its PDF.
public struct Boon: Hashable, Codable, Sendable, Identifiable {
    /// The character's name; the Boons tab doesn't show the character number.
    public let characterName: String
    public let name: String
    public let summary: String
    public let quantity: Int
    public let isConsumable: Bool
    /// Uses left on a consumable boon, when the site shows a number.
    public let remainingUses: Int?
    public let downloadURL: URL

    public init(fields: BoonFields) {
        characterName = fields.characterName
        name = fields.name
        summary = fields.summary
        quantity = fields.quantity
        isConsumable = fields.isConsumable
        remainingUses = fields.remainingUses
        downloadURL = fields.downloadURL
    }

    /// paizo.com's own keys for the character and the reward, from the download link; they stay the same across
    /// refreshes. The name stands in when the link has neither.
    public var id: String {
        let items = URLComponents(url: downloadURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let keys = ["character", "reward"].compactMap { name in items.first { $0.name == name }?.value }
        return keys.count == 2 ? keys.joined(separator: "/") : "\(characterName)/\(name)"
    }
}

/// The values a `Boon` is made from, so it isn't built from a long argument list.
public struct BoonFields: Sendable {
    public var characterName = ""
    public var name = ""
    public var summary = ""
    public var quantity = 1
    public var isConsumable = false
    public var remainingUses: Int?
    public var downloadURL = URL(fileURLWithPath: "/")

    public init() {}
}
