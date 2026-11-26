import Bestiary
import ChronicleKeeperKit
import CreatureImport
import Foundation
import SourceAttribution

/// What the item price import found.
public struct ItemPriceImportReport: Sendable {
    public var itemCount = 0
    /// Items per game, for the report.
    public var games: [ItemGame: Int] = [:]
}

/// Reads every priced item of both games' equipment packs in the pf2e system repository and writes
/// `<output>/items.json`, with the licenses the item data is used under in `<output>/Licenses`: the ORC and OGL
/// notices that name every source book an item came from (tabletop-kit's `SourceAttribution`). The import fails,
/// listing them, when a source can't be attributed, so no item ships without its book's notice.
public struct ItemPriceImporter {
    /// Folders of the equipment packs whose items no player buys.
    static let skippedFolders: Set<String> = ["virtual-items", "bestiary-items"]
    /// What a character can buy. Treasure (gems, art objects) and effects are left out.
    static let itemTypes: Set<String> = ["weapon", "armor", "shield", "equipment", "consumable", "backpack", "kit"]
    public var repository: URL
    public var outputDirectory: URL

    public init(repository: URL, outputDirectory: URL) {
        self.repository = repository
        self.outputDirectory = outputDirectory
    }

    @discardableResult
    public func run() throws -> ItemPriceImportReport {
        let items = try readItems()
        try write(items)
        var report = ItemPriceImportReport(itemCount: items.count)
        report.games = Dictionary(grouping: items, by: \.game).mapValues(\.count)
        return report
    }

    /// The items of both games, sorted by game, name and id, so the same input gives the same output.
    func readItems() throws -> [PricedItem] {
        let scanner = PackScanner(repository: repository)
        var items: [PricedItem] = []
        for game in Bestiary.Game.allCases {
            for pack in try scanner.packs(of: game, type: "Item") where pack.name == "equipment" {
                for file in scanner.documentFiles(in: pack) where !isSkipped(file) {
                    let document = try PackValue(contentsOf: file)
                    if let item = Self.item(from: document, game: ItemGame(rawValue: game.rawValue) ?? .pathfinder) {
                        items.append(item)
                    }
                }
            }
        }
        return items.sorted { ($0.game.rawValue, $0.name, $0.id) < ($1.game.rawValue, $1.name, $1.id) }
    }

    /// The item, or nil for a document that isn't something to buy, has no name or has no price.
    static func item(from document: PackValue, game: ItemGame) -> PricedItem? {
        let name = document["name"].string
        let system = document["system"]
        guard itemTypes.contains(document["type"].string), !name.isEmpty,
              let price = ItemPrice.copper(system["price"], game: game) else { return nil }
        return PricedItem(
            id: "\(game.rawValue)/\(document["_id"].string)", game: game, name: name,
            level: system[path: "level.value"].int, price: price, batchSize: ItemPrice.batchSize(system["price"]),
            rarity: Rarity(rawValue: system[path: "traits.rarity"].string) ?? .common,
            source: system[path: "publication.title"].string)
    }

    private func isSkipped(_ file: URL) -> Bool {
        file.pathComponents.contains { Self.skippedFolders.contains($0) }
    }

    private func write(_ items: [PricedItem]) throws {
        let licenses = outputDirectory.appendingPathComponent("Licenses", isDirectory: true)
        try? FileManager.default.removeItem(at: licenses)
        try FileManager.default.createDirectory(at: licenses, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(items).write(to: outputDirectory.appendingPathComponent("items.json"), options: .atomic)
        try NoticeWriter.write(for: Self.sources(of: items), catalog: try SourceCatalog.bundled(), to: licenses)
    }

    /// The source books the items came from, with how many items each gave.
    static func sources(of items: [PricedItem]) -> SourceTally {
        var tally = SourceTally()
        items.forEach { tally.add($0.source) }
        return tally
    }
}
