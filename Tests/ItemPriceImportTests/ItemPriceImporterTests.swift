import CreatureImport
import ChronicleKeeperKit

import Foundation
import Testing

@testable import ItemPriceImport

@Suite("Item price import")
struct ItemPriceImporterTests {
    @Test("coins add up to copper")
    func coinPrice() throws {
        let price = try json(["value": ["pp": 1, "gp": 2, "sp": 3, "cp": 4]])
        #expect(ItemPrice.copper(price, game: .pathfinder) == 1234)
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
                          rarity: .uncommon, source: "Core"))
        let gem = Self.document("Ruby", type: "treasure", price: ["gp": 5])
        #expect(ItemPriceImporter.item(from: try json(gem), game: .pathfinder) == nil)
        let free = Self.document("Rock", type: "equipment", price: [:])
        #expect(ItemPriceImporter.item(from: try json(free), game: .pathfinder) == nil)
        let unnamed = Self.document("", type: "equipment", price: ["gp": 1])
        #expect(ItemPriceImporter.item(from: try json(unnamed), game: .pathfinder) == nil)
    }

    @Test("writes both games' sorted items and the licenses, skipping virtual items")
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
        let licenses = try FileManager.default.contentsOfDirectory(atPath: licenseFolder.path)
        #expect(licenses.sorted() == ["ORC License.md", "Open Game License.md"])
    }

    private static func document(_ name: String, type: String, price: [String: Int]) -> [String: Any] {
        ["_id": name.filter(\.isLetter), "name": name, "type": type, "system": [
            "level": ["value": 2], "price": ["value": price], "traits": ["rarity": "uncommon"],
            "publication": ["title": "Core"]
        ]]
    }

    private static func fixtureRepository(at root: URL) throws {
        for (game, equipment) in [("pf2e", "equipment-srd"), ("sf2e", "equipment")] {
            let pack = #"{"name": "\#(equipment)", "path": "packs/\#(game)/equipment", "type": "Item"}"#
            let manifest = #"{"packs": [\#(pack)]}"#
            try write(manifest, to: root.appendingPathComponent("system.\(game).json"))
        }
        try write("ORC", to: root.appendingPathComponent("static/licenses/ORCLicense.md"))
        try write("OGL", to: root.appendingPathComponent("static/licenses/OpenGameLicense.md"))
        let sword = document("Longsword", type: "weapon", price: ["gp": 1, "sp": 5])
        let laser = document("Laser Pistol", type: "weapon", price: ["sp": 6500])
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
