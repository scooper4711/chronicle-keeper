import Foundation
import Testing
@testable import ChronicleKeeperKit

private let english = Locale(identifier: "en_US")

struct MoneyTests {
    @Test(arguments: [
        (1_120, "11 gp, 2 sp"), (0, "0 gp"), (125, "1 gp, 2 sp, 5 cp"), (5, "5 cp"), (-350, "−3 gp, 5 sp"),
        (150_000, "1,500 gp")
    ])
    func formatsGold(copper: Int, text: String) {
        #expect(Money.format(copper, in: .gold, locale: english) == text)
    }

    @Test(arguments: [(1_120, "112 credits"), (27_000, "2,700 credits"), (125, "12.5 credits"), (0, "0 credits")])
    func formatsCredits(copper: Int, text: String) {
        #expect(Money.format(copper, in: .credits, locale: english) == text)
    }

    @Test(arguments: [
        ("11.2", 1_120), ("11 gp 2 sp", 1_120), ("11gp, 2sp", 1_120), ("5 sp", 50), ("3 cp", 3), ("1,500", 150_000),
        ("0.05", 5), (" 14 ", 1_400), ("14 GP", 1_400)
    ])
    func parsesGold(text: String, copper: Int) {
        #expect(Money.parse(text, in: .gold) == copper)
    }

    @Test(arguments: ["", "abc", "-5", "1.234", "5 gold", "5 gp 3", ".", "1.2.3"])
    func rejectsWhatIsNotGold(text: String) {
        #expect(Money.parse(text, in: .gold) == nil)
    }

    @Test(arguments: [("112", 1_120), ("2,700 credits", 27_000), ("12.5", 125), ("150 cr", 1_500)])
    func parsesCredits(text: String, copper: Int) {
        #expect(Money.parse(text, in: .credits) == copper)
    }

    @Test func rejectsAFractionOfACopperInCredits() {
        #expect(Money.parse("1.25", in: .credits) == nil)
    }
}

struct RewardTablesTests {
    private let pathfinder = CampaignRules(campaign: .pathfinder2)
    private let starfinder = CampaignRules(campaign: .starfinder2)

    @Test func onlySecondEditionSocietyCampaignsHaveALedger() {
        #expect(pathfinder.hasLedger && starfinder.hasLedger)
        #expect(!CampaignRules(campaign: .pathfinder1).hasLedger)
        #expect(!CampaignRules(campaign: .starfinder1).hasLedger)
        #expect(!CampaignRules(campaign: .other("X")).hasLedger)
        #expect(pathfinder.currency == .gold && starfinder.currency == .credits)
    }

    @Test(arguments: [(1, 1_500), (3, 7_500), (5, 27_000), (7, 72_000), (2, 1_500)])
    func pathfinderStartingGold(level: Int, copper: Int) {
        #expect(pathfinder.startingFunds(level: level) == copper)
    }

    @Test(arguments: [(1, 1_500), (3, 7_500), (5, 27_000), (7, 72_000)])
    func starfinderStartingCredits(level: Int, copper: Int) {
        #expect(starfinder.startingFunds(level: level) == copper)
    }

    /// Lorespire's Treasure Bundles table, "10 TB" column, in gold pieces.
    @Test func theHintIsTenTreasureBundles() {
        let gold: [Double] = [14, 22, 38, 64, 100, 150, 220, 300, 440, 600, 860, 1_240, 1_880, 2_740, 4_080, 6_200,
                              9_600, 15_600, 26_600, 36_800]
        for (index, amount) in gold.enumerated() {
            #expect(pathfinder.fundsHint(level: index + 1) == Int(amount * 100))
        }
        #expect(pathfinder.fundsHint(level: 21) == nil)
    }

    @Test func theStarfinderHintIsTheCreditsAwarded() {
        #expect(starfinder.fundsHint(level: 1) == 1_400)
        #expect(starfinder.fundsHint(level: 10) == 60_000)
        #expect(starfinder.fundsHint(level: 11) == nil)
        #expect(CampaignRules(campaign: .pathfinder1).fundsHint(level: 1) == nil)
    }
}

struct PurchaseLegalityTests {
    private func item(level: Int, rarity: Rarity = .common) -> Purchase {
        Purchase(name: "Thing", level: level, rarity: rarity, unitPrice: 100)
    }

    @Test func aFirstLevelCharacterMayBuySecondLevelItems() {
        #expect(PurchaseLegality.itemLevelLimit(characterLevel: 1) == 2)
        #expect(PurchaseLegality.marks(for: item(level: 2), characterLevel: 1).isEmpty)
        #expect(PurchaseLegality.marks(for: item(level: 3), characterLevel: 1) == [.aboveLevel(itemLevel: 3, limit: 2)])
    }

    @Test func itemsAboveTheCharactersLevelAreMarked() {
        #expect(PurchaseLegality.marks(for: item(level: 5), characterLevel: 5).isEmpty)
        #expect(PurchaseLegality.marks(for: item(level: 6), characterLevel: 5) == [.aboveLevel(itemLevel: 6, limit: 5)])
    }

    @Test func itemsThatArentCommonAreMarkedWithTheReason() {
        let marks = PurchaseLegality.marks(for: item(level: 1, rarity: .uncommon), characterLevel: 1)
        #expect(marks == [.notCommon(.uncommon)])
        #expect(marks[0].explanation == "Uncommon: needs Access, such as from a Chronicle.")
        #expect(LegalityMark.aboveLevel(itemLevel: 5, limit: 2).explanation.contains("(2)"))
    }

    @Test func anUnknownRarityReadsAsUncommon() throws {
        let rarity = try JSONDecoder().decode([Rarity].self, from: Data(#"["Rare", "mythic"]"#.utf8))
        #expect(rarity == [.rare, .uncommon])
    }
}
