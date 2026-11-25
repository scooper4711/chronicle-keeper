import Foundation
import Testing
@testable import ChronicleKeeperKit

struct ItemPriceListTests {
    private let list = ItemPriceList(items: [
        PricedItem(id: "1", game: .pathfinder, name: "Longsword", level: 0, price: 100),
        PricedItem(id: "2", game: .pathfinder, name: "Cold Iron Longsword", level: 2, price: 4_000),
        PricedItem(id: "3", game: .pathfinder, name: "Longbow", level: 0, price: 6_000),
        PricedItem(id: "4", game: .starfinder, name: "Longsword Blade", level: 1, price: 50)
    ])

    @Test func namesStartingWithTheTextComeFirst() {
        #expect(list.suggestions(for: "longsword", game: .pathfinder).map(\.id) == ["1", "2"])
    }

    @Test func everyTypedWordMustMatch() {
        #expect(list.suggestions(for: "iron sword", game: .pathfinder).map(\.id) == ["2"])
        #expect(list.suggestions(for: "  ", game: .pathfinder).isEmpty)
    }

    @Test func onlyTheGamesItemsAndOnlyUpToTheLimit() {
        #expect(list.suggestions(for: "long", game: .starfinder).map(\.id) == ["4"])
        #expect(list.suggestions(for: "long", game: .pathfinder, limit: 1).map(\.id) == ["3"])
    }

    @Test func aPickedItemBecomesAPurchase() {
        let purchase = list.items[1].purchase(after: "1234#1", quantity: 2)
        #expect(purchase.itemID == "2" && purchase.name == "Cold Iron Longsword")
        #expect(purchase.cost == 8_000 && purchase.level == 2 && purchase.boughtAfter == "1234#1")
    }

    /// Candles are 1 cp for 10: a purchase counts batches, so two of them cost 2 cp, not 20.
    @Test func anItemSoldInBatchesIsBoughtByTheBatch() {
        let candles = PricedItem(id: "5", game: .pathfinder, name: "Candle", level: 0, price: 1, batchSize: 10)
        let purchase = candles.purchase(after: "", quantity: 2)
        #expect(purchase.name == "Candle (10)")
        #expect(purchase.unitPrice == 1 && purchase.cost == 2)
        #expect(list.items[0].purchaseName == "Longsword")
    }

    @Test func itemsAreFoundByID() {
        #expect(list.item(id: "3")?.name == "Longbow")
        #expect(list.item(id: "missing") == nil)
    }

    @Test func campaignsMapToTheirGame() {
        #expect(ItemGame(campaign: .pathfinder2) == .pathfinder)
        #expect(ItemGame(campaign: .starfinder2) == .starfinder)
        #expect(ItemGame(campaign: .pathfinder1) == nil)
        _ = ItemPriceList.bundled.items
    }
}
