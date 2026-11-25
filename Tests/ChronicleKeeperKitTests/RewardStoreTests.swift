import Foundation
import Testing
@testable import ChronicleKeeperKit

/// Hands out a catalog, or fails, and counts how often it was asked.
private final class StubRewardSource: RewardCatalogSource, @unchecked Sendable {
    private let lock = NSLock()
    private var answer: Result<RewardCatalog, Error>
    private var asked = 0

    init(_ catalog: RewardCatalog) { answer = .success(catalog) }

    var timesAsked: Int { lock.withLock { asked } }

    func answer(with result: Result<RewardCatalog, Error>) { lock.withLock { answer = result } }

    func rewardCatalog() async throws -> RewardCatalog {
        try lock.withLock {
            asked += 1
            return answer
        }.get()
    }
}

@MainActor
@Suite("The store's reward lists")
struct RewardStoreTests {
    private let number = "123456-2001"
    private let doctor = "PFS (2ed) Scenario #6-03: Is There a Doctor in the House?"

    private func catalog(readDaysAgo days: Double = 0, names: [String]? = nil) throws -> RewardCatalog {
        let offers = try RewardConditions.offers().filter { names?.contains($0.name) ?? true }
        return RewardCatalog(offers: offers, fetchedAt: Date().addingTimeInterval(-days * 24 * 60 * 60))
    }

    /// One character who played #6-03 and has the boons named.
    private func snapshot(
        owning boons: [String] = [], characters names: [String] = ["Valeria Stonebrook"]
    ) -> AccountSnapshot {
        let summaries = names.enumerated().map { index, name in
            CharacterSummary(
                number: "123456-200\(index + 1)", campaign: .pathfinder2, name: name, factions: [], standing: [])
        }
        return AccountSnapshot(
            characters: summaries, sessions: [SessionFactory.session(title: "#6-03: Godsrain in a Godless Land")],
            boons: boons.map { RewardFactory.boon($0) }, fetchedAt: Date(timeIntervalSince1970: 1_780_000_000))
    }

    private func store(
        _ repository: CharacterRepository = InMemoryCharacterRepository(), source: RewardCatalogSource,
        account: AccountSnapshot
    ) -> CharacterStore {
        let store = CharacterStore(repository: repository) { account }
        store.useRewardSource(source)
        return store
    }

    @Test("A refresh reads the lists, saves them and finds what each character may claim")
    func aRefreshReadsTheLists() async throws {
        let repository = InMemoryCharacterRepository()
        let source = StubRewardSource(try catalog())
        let store = store(repository, source: source, account: snapshot())
        #expect(store.claimableRewards(for: number).isEmpty)
        await store.refresh()
        await store.waitForRewards()
        #expect(store.claimableRewards(for: number).map(\.title) == [doctor])
        #expect(try repository.loadRewardCatalog()?.offers.count == 333)
        #expect(source.timesAsked == 1)
    }

    @Test("Lists read less than 30 days ago are not read again, and show without the network")
    func freshListsAreNotReadAgain() async throws {
        let repository = InMemoryCharacterRepository()
        try repository.saveRewardCatalog(try catalog(readDaysAgo: 3))
        try repository.saveSnapshot(snapshot())
        let source = StubRewardSource(try catalog())
        let store = store(repository, source: source, account: snapshot())
        store.load()
        #expect(store.claimableRewards(for: number).map(\.title) == [doctor])
        await store.refresh()
        await store.waitForRewards()
        #expect(source.timesAsked == 0)
    }

    @Test("Lists older than 30 days are read again after a refresh")
    func oldListsAreReadAgain() async throws {
        let repository = InMemoryCharacterRepository()
        try repository.saveRewardCatalog(try catalog(readDaysAgo: 31, names: ["Wayfinder"]))
        let source = StubRewardSource(try catalog())
        let store = store(repository, source: source, account: snapshot())
        store.load()
        await store.refresh()
        #expect(store.claimableRewards(for: number).isEmpty)
        await store.waitForRewards()
        #expect(source.timesAsked == 1)
        #expect(store.claimableRewards(for: number).map(\.title) == [doctor])
    }

    @Test("A reading that fails keeps the saved lists and shows no message")
    func aFailedReadingKeepsTheSavedLists() async throws {
        let repository = InMemoryCharacterRepository()
        let old = try catalog(readDaysAgo: 40)
        try repository.saveRewardCatalog(old)
        let source = StubRewardSource(old)
        source.answer(with: .failure(OrganizedPlayError.noCredentials))
        let store = store(repository, source: source, account: snapshot())
        store.load()
        await store.refresh()
        await store.waitForRewards()
        #expect(source.timesAsked == 1)
        #expect(store.errorMessage == nil)
        #expect(try repository.loadRewardCatalog() == old)
        #expect(store.claimableRewards(for: number).map(\.title) == [doctor])
    }

    @Test("A reading that finds no list doesn't replace lists that are there, but is kept when there are none")
    func anEmptyReading() async throws {
        let repository = InMemoryCharacterRepository()
        let old = try catalog(readDaysAgo: 40)
        try repository.saveRewardCatalog(old)
        let empty = RewardCatalog(offers: [], fetchedAt: Date())
        let kept = store(repository, source: StubRewardSource(empty), account: snapshot())
        kept.load()
        await kept.refresh()
        await kept.waitForRewards()
        #expect(try repository.loadRewardCatalog() == old)

        let bare = InMemoryCharacterRepository()
        let first = store(bare, source: StubRewardSource(empty), account: snapshot())
        await first.refresh()
        await first.waitForRewards()
        #expect(try bare.loadRewardCatalog() == empty)
        #expect(first.claimableRewards(for: number).isEmpty)
    }

    @Test("Without an account, or without a source, nothing is read")
    func nothingIsReadWithoutAnAccountOrASource() async throws {
        let source = StubRewardSource(try catalog())
        let failing = CharacterStore(repository: InMemoryCharacterRepository()) {
            throw OrganizedPlayError.noCredentials
        }
        failing.useRewardSource(source)
        await failing.refresh()
        await failing.waitForRewards()
        #expect(source.timesAsked == 0)

        let account = snapshot()
        let sourceless = CharacterStore(repository: InMemoryCharacterRepository()) { account }
        await sourceless.refresh()
        await sourceless.waitForRewards()
        #expect(sourceless.claimableRewards.isEmpty)
    }

    @Test("A refresh that brings the claimed boon takes its signal away")
    func aClaimedBoonIsNoLongerSignaled() async throws {
        let repository = InMemoryCharacterRepository()
        try repository.saveRewardCatalog(try catalog(readDaysAgo: 1))
        try repository.saveSnapshot(snapshot())
        let store = store(repository, source: StubRewardSource(try catalog()), account: snapshot(owning: [doctor]))
        store.load()
        #expect(store.claimableRewards(for: number).count == 1)
        await store.refresh()
        #expect(store.claimableRewards(for: number).isEmpty)
    }

    @Test("Characters who share a name get no signals, as their boons can't be told apart")
    func namesakesGetNoSignals() async throws {
        let account = snapshot(characters: ["Valeria Stonebrook", "valeria stonebrook"])
        let store = store(source: StubRewardSource(try catalog()), account: account)
        await store.refresh()
        await store.waitForRewards()
        #expect(store.claimableRewards.isEmpty)
    }

    @Test("Signing out stops a reading, forgets the claims and keeps the lists")
    func signingOut() async throws {
        let repository = InMemoryCharacterRepository()
        let store = store(repository, source: StubRewardSource(try catalog()), account: snapshot())
        await store.refresh()
        await store.waitForRewards()
        await store.refresh()
        store.signOut()
        #expect(store.claimableRewards.isEmpty)
        #expect(store.rewardFetch == nil)
        #expect(try repository.loadRewardCatalog()?.offers.count == 333)
    }

    @Test("The demo's lists give its characters rewards to claim, a choice among them")
    func theDemoHasRewardsToClaim() async throws {
        let account = DemoAccount.snapshot(fetchedAt: Date())
        let store = store(source: DemoRewards.Source(), account: account)
        await store.refresh()
        await store.waitForRewards()
        let valeria = store.claimableRewards(for: "\(DemoAccount.playerNumber)-2001")
        #expect(valeria.map(\.title) == [
            "PFS (2ed) Scenario #6-05: Ashes Over Highhelm: Boon A or Boon B",
            "PFS (2ed) Scenario #6-09: Glass Sea Pearl", "Rugged Mentor (Horizon Hunters)"
        ])
        let pip = store.claimableRewards(for: "\(DemoAccount.playerNumber)-2002")
        #expect(pip.map(\.title) == ["Wayfinder"])
        #expect(store.claimableRewards.count == 4)
    }
}
