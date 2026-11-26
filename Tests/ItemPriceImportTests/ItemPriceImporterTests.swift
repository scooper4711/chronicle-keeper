import CreatureImport
import ChronicleKeeperKit

import Foundation
import SourceAttribution
import Testing

@testable import ItemPriceImport

@Suite("Item price import")
struct ItemPriceImporterTests {
    @Test("coins add up to copper")
    func coinPrice() throws {
        let price = try json(["value": ["pp": 1, "gp": 2, "sp": 3, "cp": 4]])
        #expect(ItemPrice.copper(price, game: .pathfinder) == 1234)
    }

    /// Prices below a gold piece, as the Core Rulebook has them: a torch, flint and steel, rations, a candle (per 10).
    @Test("prices below a gold piece stay exact", arguments: [
        (["cp": 1], 1, "0.01 gp"), (["cp": 5], 5, "0.05 gp"), (["sp": 4], 40, "0.4 gp"),
        (["sp": 3, "cp": 2], 32, "0.32 gp")
    ])
    func priceBelowAGoldPiece(coins: [String: Int], copper: Int, shown: String) throws {
        let price = try ItemPrice.copper(json(["value": coins]), game: .pathfinder)
        #expect(price == copper)
        #expect(Money.format(copper, in: .gold, locale: Locale(identifier: "en_US")) == shown)
    }

    @Test("a Starfinder credit is a silver piece, and UPBs are no coin")
    func creditPrice() throws {
        #expect(ItemPrice.copper(try json(["value": ["sp": 6500]]), game: .starfinder) == 65_000)
        #expect(ItemPrice.copper(try json(["value": ["upb": 40]]), game: .starfinder) == nil)
    }

    @Test("no coins means no price, and a batch is at least one")
    func noPrice() throws {
        #expect(ItemPrice.copper(try json(["value": [:]]), game: .pathfinder) == nil)
        #expect(ItemPrice.batchSize(try json(["per": 10])) == 10)
        #expect(ItemPrice.batchSize(try json(["value": [:]])) == 1)
    }

    @Test("reads a purchasable item and skips the rest")
    func readsItems() throws {
        let sword = Self.document("Longsword", type: "weapon", price: ["gp": 1, "sp": 5])
        #expect(ItemPriceImporter.item(from: try json(sword), game: .pathfinder)
            == PricedItem(id: "pf2e/Longsword", game: .pathfinder, name: "Longsword", level: 2, price: 150,
                          rarity: .uncommon, source: "Pathfinder Player Core"))
        let gem = Self.document("Ruby", type: "treasure", price: ["gp": 5])
        #expect(ItemPriceImporter.item(from: try json(gem), game: .pathfinder) == nil)
        let free = Self.document("Rock", type: "equipment", price: [:])
        #expect(ItemPriceImporter.item(from: try json(free), game: .pathfinder) == nil)
        let unnamed = Self.document("", type: "equipment", price: ["gp": 1])
        #expect(ItemPriceImporter.item(from: try json(unnamed), game: .pathfinder) == nil)
    }

    @Test("writes both games' sorted items and their sources' notices, skipping virtual items")
    func writesList() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("prices-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.fixtureRepository(at: root)
        let output = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let report = try ItemPriceImporter(repository: root, outputDirectory: output).run()

        let data = try Data(contentsOf: output.appendingPathComponent("items.json"))
        let items = try JSONDecoder().decode([PricedItem].self, from: data)
        #expect(items.map(\.name) == ["Longsword", "Laser Pistol"])
        #expect(report.itemCount == 2)
        #expect(report.games == [.pathfinder: 1, .starfinder: 1])
        let licenseFolder = output.appendingPathComponent("Licenses")
        // Both fixture books are under the ORC License, so no OGL notice is written.
        #expect(try FileManager.default.contentsOfDirectory(atPath: licenseFolder.path) == ["ORC License.md"])
        let notice = try String(contentsOf: licenseFolder.appendingPathComponent("ORC License.md"), encoding: .utf8)
        #expect(notice.contains("Pathfinder Player Core ©") && notice.contains("Starfinder Player Core ©"))
        #expect(!notice.hasPrefix("/static"))
    }

    @Test("an item from a book the catalog doesn't know stops the import, naming the book")
    func unknownSourceFails() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("prices-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.fixtureRepository(at: root)
        let rope = Self.document("Rope", type: "equipment", price: ["sp": 5], source: "A Book Nobody Wrote")
        try Self.write(rope, to: root.appendingPathComponent("packs/pf2e/equipment/rope.json"))
        let output = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let error = #expect(throws: AttributionError.self) {
            try ItemPriceImporter(repository: root, outputDirectory: output).run()
        }
        #expect(error?.description.contains("A Book Nobody Wrote: not in the catalog") == true)
    }

    /// The item data the app ships is made by `make items` and isn't in the repository, so this runs wherever the
    /// import has run: on a developer's Mac and in the release builds.
    @Test("every source of the bundled items is named in exactly one notice",
          .enabled(if: !ItemPriceList.bundled.items.isEmpty, "needs the item data that make items writes"))
    func bundledSourcesAreAttributed() throws {
        let folder = try #require(ItemPriceList.licensesFolder)
        let catalog = try SourceCatalog.bundled()
        let notices = try [NoticeWriter.orcFileName, NoticeWriter.oglFileName].compactMap { name in
            try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
        }
        #expect(!notices.isEmpty)
        for source in Set(ItemPriceList.bundled.items.map(\.source)).sorted() {
            let entry = try #require(catalog.entry(for: source), "\(source) isn't in the catalog")
            // A collection, such as the Pathfinder Blog, is named by the notices of its parts.
            let lines = entry.isCollection ? entry.includes : [entry.noticeLine]
            let naming = notices.filter { notice in lines.allSatisfy(notice.contains) }
            #expect(naming.count == 1, "\(source) is named in \(naming.count) notices")
        }
    }

    private static func document(
        _ name: String, type: String, price: [String: Int], source: String = "Pathfinder Player Core"
    ) -> [String: Any] {
        ["_id": name.filter(\.isLetter), "name": name, "type": type, "system": [
            "level": ["value": 2], "price": ["value": price], "traits": ["rarity": "uncommon"],
            "publication": ["title": source]
        ]]
    }

    private static func fixtureRepository(at root: URL) throws {
        for (game, equipment) in [("pf2e", "equipment-srd"), ("sf2e", "equipment")] {
            let pack = #"{"name": "\#(equipment)", "path": "packs/\#(game)/equipment", "type": "Item"}"#
            let manifest = #"{"packs": [\#(pack)]}"#
            try write(manifest, to: root.appendingPathComponent("system.\(game).json"))
        }
        let sword = document("Longsword", type: "weapon", price: ["gp": 1, "sp": 5])
        let laser = document("Laser Pistol", type: "weapon", price: ["sp": 6500], source: "Starfinder Player Core")
        let virtual = document("Virtual", type: "equipment", price: ["gp": 1])
        try write(sword, to: root.appendingPathComponent("packs/pf2e/equipment/longsword.json"))
        try write(laser, to: root.appendingPathComponent("packs/sf2e/equipment/laser-pistol.json"))
        try write(virtual, to: root.appendingPathComponent("packs/pf2e/equipment/virtual-items/virtual.json"))
    }

    private static func write(_ document: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: document)
        try write(String(bytes: data, encoding: .utf8) ?? "", to: url)
    }

    private static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func json(_ object: [String: Any]) throws -> CreatureImport.JSONValue {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("doc-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try JSONSerialization.data(withJSONObject: object).write(to: file)
        return try CreatureImport.JSONValue(contentsOf: file)
    }
}
