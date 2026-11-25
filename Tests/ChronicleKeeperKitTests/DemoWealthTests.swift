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

    @Test func zixsLedgerIsInCreditsWithAnUncommonItem() async throws {
        let ledger = try await demoLedger(of: "123456-701")
        let marks = lines(of: ledger).flatMap { line -> [LegalityMark] in
            if case .purchase(_, let marks) = line.entry { return marks }
            return []
        }
        #expect(ledger.currency == .credits)
        #expect(marks == [.notCommon(.uncommon)])
        #expect(!ledger.isOverspent)
    }

    @Test func theRepositoryStartsWithTheSettingsItWasGiven() throws {
        let repository = InMemoryCharacterRepository(settings: DemoWealth.settings)
        #expect(try repository.loadSettings().keys.sorted() == ["123456-2001", "123456-701"])
    }
}
