import Foundation
import Testing
@testable import ChronicleKeeperKit

/// A character with `count` scenarios of 4 XP each, played a day apart, keyed "1234#1", "1234#2"…
enum WealthFactory {
    static let number = "123456-2001"

    static func key(_ index: Int) -> String { "1234#\(index)" }

    static func record(
        sessions count: Int = 3, campaign: Campaign = .pathfinder2, wealth: CharacterWealth = CharacterWealth(),
        startingLevel: Int = 1
    ) -> CharacterRecord {
        let sessions = (1...max(count, 1)).prefix(count).map { index in
            SessionFactory.session(
                date: Date(timeIntervalSince1970: 1_780_000_000 + Double(index) * 86_400), sessionNumber: index)
        }
        var settings = CharacterSettings(startingLevel: startingLevel)
        settings.wealth = wealth
        let summary = CharacterSummary(
            number: number, campaign: campaign, name: "Valeria Stonebrook", factions: [], standing: [])
        return CharacterRoster(summaries: [summary], sessions: sessions, settings: [number: settings]).characters[0]
    }

    static func purchase(
        _ id: String, price: Int, after key: String = "", level: Int = 1, rarity: Rarity = .common, second: Double = 0
    ) -> Purchase {
        Purchase(id: id, name: id, level: level, rarity: rarity, unitPrice: price, boughtAfter: key,
                 addedAt: Date(timeIntervalSince1970: second))
    }
}

struct WealthLedgerTests {
    private typealias Factory = WealthFactory

    @Test func theBalanceRunsThroughGoldPurchasesAndSales() {
        var wealth = CharacterWealth(earned: [Factory.key(1): 1_400])
        wealth.add(Factory.purchase("rope", price: 400))
        wealth.add(Factory.purchase("sword", price: 1_000, after: Factory.key(1)))
        wealth.sell("rope", after: Factory.key(2), in: LedgerOrder(keys: (1...3).map(Factory.key)))
        let ledger = WealthLedger(record: Factory.record(wealth: wealth))
        #expect(ledger.groups.map(\.id) == ["", Factory.key(1), Factory.key(2), Factory.key(3)])
        #expect(ledger.groups[0].lines.map(\.balance) == [1_500, 1_100])
        #expect(ledger.groups[1].lines.map(\.balance) == [2_500, 1_500])
        #expect(ledger.groups[2].lines.map(\.id) == ["earned", "sale-rope"])
        #expect(ledger.groups[2].lines.map(\.balance) == [1_500, 1_700])
        #expect(ledger.balance == 1_700)
        #expect(ledger.adventuresWithoutGold == 2)
        #expect(!ledger.isOverspent)
        #expect(ledger.currency == .gold)
    }

    @Test func anEmptyGoldFieldCountsAsNothing() {
        let ledger = WealthLedger(record: Factory.record(sessions: 2))
        #expect(ledger.groups[1].lines[0].entry == .earned(nil))
        #expect(ledger.groups[1].lines[0].amount == 0)
        #expect(ledger.balance == 1_500)
        #expect(ledger.adventuresWithoutGold == 2)
    }

    @Test func salesComeBeforePurchasesAfterTheSameAdventure() {
        var wealth = CharacterWealth()
        wealth.add(Factory.purchase("old", price: 1_000))
        wealth.add(Factory.purchase("new", price: 1_000, after: Factory.key(1)))
        wealth.sell("old", after: Factory.key(1), in: LedgerOrder(keys: [Factory.key(1)]))
        let lines = WealthLedger(record: Factory.record(sessions: 1, wealth: wealth)).groups[1].lines
        #expect(lines.map(\.id) == ["earned", "sale-old", "purchase-new"])
    }

    @Test func overspendingIsShownAndMovingThePurchaseLaterClearsIt() {
        var wealth = CharacterWealth(earned: [Factory.key(1): 1_400])
        wealth.add(Factory.purchase("armor", price: 2_000))
        let record = Factory.record(wealth: wealth)
        let before = WealthLedger(record: record)
        #expect(before.isOverspent)
        #expect(before.groups[0].lines.last?.balance == -500)
        wealth.move("armor", to: Factory.key(1), in: before.order)
        #expect(!WealthLedger(record: Factory.record(wealth: wealth)).isOverspent)
    }

    @Test func theLevelMarkFollowsThePurchaseWhenItMoves() throws {
        var wealth = CharacterWealth()
        wealth.add(Factory.purchase("wand", price: 100, level: 3))
        let before = WealthLedger(record: Factory.record(sessions: 6, wealth: wealth))
        #expect(marks(of: "wand", in: before) == [.aboveLevel(itemLevel: 3, limit: 2)])
        // Six scenarios of 4 XP take a 1st-level character to 3rd.
        wealth.move("wand", to: Factory.key(6), in: before.order)
        let after = WealthLedger(record: Factory.record(sessions: 6, wealth: wealth))
        #expect(after.groups.last?.characterLevel == 3)
        #expect(marks(of: "wand", in: after) == [])
    }

    @Test func rarityIsMarkedWherever() {
        var wealth = CharacterWealth()
        wealth.add(Factory.purchase("charm", price: 100, rarity: .rare))
        #expect(marks(of: "charm", in: WealthLedger(record: Factory.record(wealth: wealth))) == [.notCommon(.rare)])
    }

    @Test func purchasesOfAnAdventureNoLongerListedAreKeptLast() {
        var wealth = CharacterWealth()
        wealth.add(Factory.purchase("lost", price: 100, after: "9999#9"))
        let ledger = WealthLedger(record: Factory.record(sessions: 1, wealth: wealth))
        #expect(ledger.groups.last?.place == .unlisted)
        #expect(ledger.groups.last?.lines.map(\.id) == ["purchase-lost"])
        #expect(ledger.balance == 1_400)
        #expect(WealthLedger(record: Factory.record(sessions: 1)).groups.last?.place != .unlisted)
    }

    @Test func purchasesAfterOneAdventureKeepTheOrderTheyWereAdded() {
        var wealth = CharacterWealth()
        wealth.add(Factory.purchase("b", price: 1, second: 2))
        wealth.add(Factory.purchase("a", price: 1, second: 3))
        wealth.add(Factory.purchase("c", price: 1, second: 2))
        let lines = WealthLedger(record: Factory.record(sessions: 0, wealth: wealth)).groups[0].lines
        #expect(lines.map(\.id) == ["start", "purchase-b", "purchase-c", "purchase-a"])
    }

    @Test func startingFundsFollowTheStartingLevelUnlessChanged() {
        #expect(WealthLedger(record: Factory.record(sessions: 0, startingLevel: 5)).balance == 27_000)
        let credits = WealthLedger(record: Factory.record(sessions: 0, campaign: .starfinder2))
        #expect(credits.balance == 1_500 && credits.currency == .credits)
        let changed = WealthLedger(record: Factory.record(sessions: 0, wealth: CharacterWealth(startingFunds: 42)))
        #expect(changed.balance == 42)
    }

    private func marks(of id: String, in ledger: WealthLedger) -> [LegalityMark]? {
        for line in ledger.groups.flatMap(\.lines) {
            if case let .purchase(purchase, marks) = line.entry, purchase.id == id { return marks }
        }
        return nil
    }
}

struct CharacterWealthTests {
    private let order = LedgerOrder(keys: ["a", "b", "c"])

    private func wealth(boughtAfter: String, soldAfter: String? = nil) -> CharacterWealth {
        var wealth = CharacterWealth()
        wealth.add(WealthFactory.purchase("x", price: 100, after: boughtAfter))
        if let soldAfter { wealth.sell("x", after: soldAfter, in: order) }
        return wealth
    }

    @Test func movingAPurchasePastItsSaleTakesTheSaleAlong() {
        var value = wealth(boughtAfter: "a", soldAfter: "b")
        value.move("x", to: "c", in: order)
        #expect(value.purchases["x"]?.boughtAfter == "c")
        #expect(value.purchases["x"]?.soldAfter == "c")
    }

    @Test func movingAPurchaseEarlierLeavesTheSaleWhereItIs() {
        var value = wealth(boughtAfter: "b", soldAfter: "c")
        value.move("x", to: "", in: order)
        #expect(value.purchases["x"]?.boughtAfter == "")
        #expect(value.purchases["x"]?.soldAfter == "c")
    }

    @Test func aSaleIsNeverPlacedBeforeItsPurchase() {
        var value = wealth(boughtAfter: "b", soldAfter: "a")
        #expect(value.purchases["x"]?.soldAfter == "b")
        value.sell("x", after: "c", in: order)
        #expect(value.purchases["x"]?.soldAfter == "c")
        value.undoSale(of: "x")
        #expect(value.purchases["x"]?.isSold == false)
    }

    @Test func aSaleGivesBackHalfOfWhatWasPaid() {
        var purchase = WealthFactory.purchase("arrows", price: 5)
        purchase.quantity = 3
        #expect(purchase.cost == 15)
        #expect(purchase.saleValue == 7)
    }

    @Test func anUnknownKeyComesLast() {
        #expect(order.position(of: "") == 0)
        #expect(order.position(of: "c") == 3)
        #expect(order.later("gone", "c") == "gone")
        var value = wealth(boughtAfter: "a")
        value.move("missing", to: "b", in: order)
        value.remove("x")
        #expect(value.isEmpty)
    }

    @Test func purchaseDatesAreWholeSeconds() {
        let purchase = Purchase(name: "x", unitPrice: 1, addedAt: Date(timeIntervalSince1970: 10.75))
        #expect(purchase.addedAt == Date(timeIntervalSince1970: 10))
    }
}
