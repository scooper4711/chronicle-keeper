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

    /// The name a purchase of it carries: "Candle (10)" for an item sold in batches, since its price and a
    /// purchase's quantity count batches, not single items.
    public var purchaseName: String {
        batchSize > 1 ? "\(name) (\(batchSize))" : name
    }

    /// A new purchase of this item; `quantity` counts batches.
    public func purchase(after key: String, quantity: Int = 1) -> Purchase {
        Purchase(
            itemID: id, name: purchaseName, level: level, rarity: rarity, unitPrice: price, quantity: quantity,
            boughtAfter: key)
    }
}

/// The items a purchase can be picked from, searched as the user types (R5.3).
public struct ItemPriceList: Sendable {
    public let items: [PricedItem]
    private let byID: [String: PricedItem]

    public init(items: [PricedItem]) {
        self.items = items
        byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The item with this ID, as a picked purchase names it; nil when the item data has none.
    public func item(id: String) -> PricedItem? {
        byID[id]
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

    /// The folder with the ORC and OGL license files `make items` copied beside the list, or nil without them.
    public static var licensesFolder: URL? {
        Bundle.module.url(forResource: "Licenses", withExtension: nil, subdirectory: "Items")
    }

    private static func loadBundled() -> [PricedItem] {
        guard let url = Bundle.module.url(forResource: "items", withExtension: "json", subdirectory: "Items"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PricedItem].self, from: data)) ?? []
    }
}
