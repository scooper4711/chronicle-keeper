import Foundation

/// Which game's item data an item comes from.
public enum ItemGame: String, Hashable, Codable, Sendable {
    case pathfinder = "pf2e"
    case starfinder = "sf2e"

    /// The game whose items a campaign buys; nil for a campaign without a ledger.
    public init?(campaign: Campaign) {
        switch campaign {
        case .pathfinder2: self = .pathfinder
        case .starfinder2: self = .starfinder
        default: return nil
        }
    }
}

/// An item with a price, as the import writes it to `items.json`.
public struct PricedItem: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let game: ItemGame
    public let name: String
    public let level: Int
    /// The price of one batch, in copper.
    public let price: Int
    /// How many come for that price (ammunition and the like); 1 for most items.
    public let batchSize: Int
    public let rarity: Rarity
    public let source: String

    public init(
        id: String, game: ItemGame, name: String, level: Int, price: Int,
        batchSize: Int = 1, rarity: Rarity = .common, source: String = ""
    ) {
        self.id = id
        self.game = game
        self.name = name
        self.level = level
        self.price = price
        self.batchSize = batchSize
        self.rarity = rarity
        self.source = source
    }

    /// A new purchase of this item.
    public func purchase(after key: String, quantity: Int = 1) -> Purchase {
        Purchase(
            itemID: id, name: name, level: level, rarity: rarity, unitPrice: price, quantity: quantity,
            boughtAfter: key)
    }
}

/// The items a purchase can be picked from, searched as the user types (R5.3).
public struct ItemPriceList: Sendable {
    public let items: [PricedItem]

    public init(items: [PricedItem]) {
        self.items = items
    }

    /// The list the build bundled, or an empty one when the build has none (`make items` wasn't run).
    public static let bundled = ItemPriceList(items: loadBundled())

    /// Items of the game whose name has every typed word, those starting with the text first, then by name.
    public func suggestions(for text: String, game: ItemGame, limit: Int = 8) -> [PricedItem] {
        let query = text.trimmingCharacters(in: .whitespaces).lowercased()
        let words = query.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let matches = items.filter { item in
            item.game == game && words.allSatisfy { item.name.lowercased().contains($0) }
        }
        return Array(matches.sorted { Self.comesFirst($0, $1, query: query) }.prefix(limit))
    }

    /// Names starting with the query first, then by name, then by level.
    private static func comesFirst(_ first: PricedItem, _ second: PricedItem, query: String) -> Bool {
        let firstName = first.name.lowercased(), secondName = second.name.lowercased()
        let firstStarts = firstName.hasPrefix(query), secondStarts = secondName.hasPrefix(query)
        if firstStarts != secondStarts { return firstStarts }
        return (firstName, first.level) < (secondName, second.level)
    }

    private static func loadBundled() -> [PricedItem] {
        guard let url = Bundle.module.url(forResource: "items", withExtension: "json", subdirectory: "Items"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PricedItem].self, from: data)) ?? []
    }
}
