import Foundation

/// How freely an item can be bought: only common items need no Access.
public enum Rarity: String, Hashable, Codable, Sendable, CaseIterable {
    case common, uncommon, rare, unique

    /// Reads a rarity from the item data or a newer version; anything unknown counts as uncommon, so it is marked
    /// rather than passed as common.
    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        self = Rarity(rawValue: text.lowercased()) ?? .uncommon
    }
}

/// Something a character bought, and its sale if it was sold (R5.3, R5.4). The item's name, level, rarity and price
/// are copied in, so the row reads the same without the item data or after it changes.
public struct Purchase: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    /// The item's ID in the item data; empty for an item typed by hand.
    public var itemID: String
    public var name: String
    public var level: Int
    public var rarity: Rarity
    /// The price of one, in copper.
    public var unitPrice: Int
    public var quantity: Int
    /// The `PlayedSession.keyWithinCharacter` of the adventure it was bought after; empty for starting gold.
    public var boughtAfter: String
    /// The key of the adventure it was sold after; nil while the character still has it.
    public var soldAfter: String?
    /// When it was added, which orders the purchases made after the same adventure.
    public var addedAt: Date
    /// Fields a newer version saved that this one doesn't know; written back as they were.
    public var unknownFields = UnknownFields()

    public init(
        id: String = UUID().uuidString, itemID: String = "", name: String, level: Int = 0, rarity: Rarity = .common,
        unitPrice: Int, quantity: Int = 1, boughtAfter: String = "", addedAt: Date = Date()
    ) {
        self.id = id
        self.itemID = itemID
        self.name = name
        self.level = level
        self.rarity = rarity
        self.unitPrice = unitPrice
        self.quantity = quantity
        self.boughtAfter = boughtAfter
        soldAfter = nil
        // Whole seconds, so the date reads back equal from every file and record it is saved in.
        self.addedAt = Date(timeIntervalSince1970: addedAt.timeIntervalSince1970.rounded(.down))
    }

    /// What it cost, in copper.
    public var cost: Int { unitPrice * quantity }

    /// What selling it gives back: half of what was paid ("Selling Gear"), rounded down to the copper.
    public var saleValue: Int { cost / 2 }

    public var isSold: Bool { soldAfter != nil }
}

extension Purchase {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, itemID, name, level, rarity, unitPrice, quantity, boughtAfter, soldAfter, addedAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        itemID = try values.decodeIfPresent(String.self, forKey: .itemID) ?? ""
        name = try values.decode(String.self, forKey: .name)
        level = try values.decodeIfPresent(Int.self, forKey: .level) ?? 0
        rarity = try values.decodeIfPresent(Rarity.self, forKey: .rarity) ?? .common
        unitPrice = try values.decode(Int.self, forKey: .unitPrice)
        quantity = try values.decodeIfPresent(Int.self, forKey: .quantity) ?? 1
        boughtAfter = try values.decodeIfPresent(String.self, forKey: .boughtAfter) ?? ""
        soldAfter = try values.decodeIfPresent(String.self, forKey: .soldAfter)
        addedAt = try values.decodeIfPresent(Date.self, forKey: .addedAt) ?? .distantPast
        unknownFields = try UnknownFields(from: decoder, known: Set(CodingKeys.allCases.map(\.stringValue)))
    }

    public func encode(to encoder: Encoder) throws {
        try unknownFields.encode(to: encoder)
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(itemID, forKey: .itemID)
        try values.encode(name, forKey: .name)
        try values.encode(level, forKey: .level)
        try values.encode(rarity, forKey: .rarity)
        try values.encode(unitPrice, forKey: .unitPrice)
        try values.encode(quantity, forKey: .quantity)
        try values.encode(boughtAfter, forKey: .boughtAfter)
        try values.encodeIfPresent(soldAfter, forKey: .soldAfter)
        try values.encode(addedAt, forKey: .addedAt)
    }
}

/// Where each adventure falls in the order credit was banked, so a sale can be kept after its purchase.
/// Starting gold (the empty key) comes first; a key no adventure has any more comes last.
public struct LedgerOrder: Sendable {
    private let positions: [String: Int]

    /// `keys` are the adventures' `keyWithinCharacter`, oldest first by `SessionProgress.applyOrder`.
    public init(keys: [String]) {
        var positions = [String: Int]()
        for (index, key) in keys.enumerated() where positions[key] == nil { positions[key] = index + 1 }
        positions[""] = 0
        self.positions = positions
    }

    public func position(of key: String) -> Int {
        positions[key] ?? Int.max
    }

    /// The later of two keys.
    public func later(_ first: String, _ second: String) -> String {
        position(of: second) > position(of: first) ? second : first
    }
}

/// A character's ledger as the user entered it (R5): the starting funds when they changed them, the gold each
/// adventure gave, and the purchases.
public struct CharacterWealth: Hashable, Codable, Sendable {
    /// The starting funds in copper when the user changed them; nil means the campaign's amount (R5.1).
    public var startingFunds: Int?
    /// Gold entered per adventure, in copper, keyed by `PlayedSession.keyWithinCharacter`. A missing key is an
    /// empty field, which counts as nothing (R5.2).
    public var earned: [String: Int]
    public var purchases: [String: Purchase]
    /// Fields a newer version saved that this one doesn't know; written back as they were.
    public var unknownFields = UnknownFields()

    public init(startingFunds: Int? = nil, earned: [String: Int] = [:], purchases: [String: Purchase] = [:]) {
        self.startingFunds = startingFunds
        self.earned = earned
        self.purchases = purchases
    }

    public var isEmpty: Bool { self == CharacterWealth() }

    public mutating func add(_ purchase: Purchase) {
        purchases[purchase.id] = purchase
    }

    public mutating func remove(_ id: String) {
        purchases[id] = nil
    }

    /// Moves a purchase to after another adventure (R5.5). A purchase moved past its own sale takes the sale along.
    public mutating func move(_ id: String, to key: String, in order: LedgerOrder) {
        guard var purchase = purchases[id] else { return }
        purchase.boughtAfter = key
        purchase.soldAfter = purchase.soldAfter.map { order.later(key, $0) }
        purchases[id] = purchase
    }

    /// Sells a purchase after an adventure, or moves its sale there. A sale is never placed before its purchase:
    /// one asked for earlier lands with the purchase (R5.4, R5.5).
    public mutating func sell(_ id: String, after key: String, in order: LedgerOrder) {
        guard var purchase = purchases[id] else { return }
        purchase.soldAfter = order.later(purchase.boughtAfter, key)
        purchases[id] = purchase
    }

    public mutating func undoSale(of id: String) {
        purchases[id]?.soldAfter = nil
    }
}

extension CharacterWealth {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case startingFunds, earned, purchases
    }

    /// Reads a ledger written by any version: a field missing gets its default, and one this version doesn't
    /// know is kept.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            startingFunds: try values.decodeIfPresent(Int.self, forKey: .startingFunds),
            earned: try values.decodeIfPresent([String: Int].self, forKey: .earned) ?? [:],
            purchases: try values.decodeIfPresent([String: Purchase].self, forKey: .purchases) ?? [:])
        unknownFields = try UnknownFields(from: decoder, known: Set(CodingKeys.allCases.map(\.stringValue)))
    }

    public func encode(to encoder: Encoder) throws {
        try unknownFields.encode(to: encoder)
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(startingFunds, forKey: .startingFunds)
        try values.encode(earned, forKey: .earned)
        try values.encode(purchases, forKey: .purchases)
    }
}
