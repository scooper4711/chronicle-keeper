import Foundation
import Testing
@testable import ChronicleKeeperKit

@MainActor
struct DemoWealthTests {
    private func demoLedger(of number: String) async throws -> WealthLedger {
        let store = CharacterStore(repository: InMemoryCharacterRepository(settings: DemoWealth.settings)) {
            DemoAccount.snapshot()
        }
        store.load()
        await store.refresh()
        let record = try #require(store.roster.characters.first { $0.id == number })
        return WealthLedger(record: record)
    }

    private func lines(of ledger: WealthLedger) -> [LedgerLine] {
        ledger.groups.flatMap(\.lines)
    }

    @Test func valeriasLedgerShowsAMarkedPurchaseASaleAndMissingGold() async throws {
        let ledger = try await demoLedger(of: "123456-2001")
        let marked = lines(of: ledger).filter {
            if case .purchase(_, let marks) = $0.entry { return !marks.isEmpty }
            return false
        }
        let sales = lines(of: ledger).filter { if case .sale = $0.entry { true } else { false } }
        #expect(marked.count == 1)
        #expect(sales.count == 1)
        #expect(ledger.adventuresWithoutGold == 3)
        #expect(!ledger.isOverspent)
        #expect(ledger.balance == 6_600)
    }

    @Test func zixsLedgerIsInCreditsWithAnUncommonItemLinkedToHisBoon() async throws {
        let ledger = try await demoLedger(of: "123456-701")
        let marked = lines(of: ledger).compactMap { line -> Purchase? in
            if case let .purchase(purchase, marks) = line.entry, marks == [.notCommon(.uncommon)] { return purchase }
            return nil
        }
        #expect(ledger.currency == .credits)
        #expect(marked.map(\.name) == ["Holo-Skin Drone"])
        #expect(marked.first?.accessLink?.sourceDescription == "Zix-7's boon Drift Beacon")
        #expect(DemoBoons.boons.contains { $0.id == marked.first?.accessLink?.sourceID })
        #expect(!ledger.isOverspent)
    }

    @Test func theRepositoryStartsWithTheSettingsItWasGiven() throws {
        let repository = InMemoryCharacterRepository(settings: DemoWealth.settings)
        #expect(try repository.loadSettings().keys.sorted() == ["123456-2001", "123456-701"])
    }
}
