import Foundation
import Testing
@testable import ChronicleKeeperKit

private func page(_ text: String) -> HTTPResponse { HTTPResponse(data: Data(text.utf8)) }

@Suite("Reward catalog")
struct RewardCatalogTests {
    private let read = Date(timeIntervalSince1970: 1_780_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    private func offer() throws -> RewardOffer {
        RewardOffer(type: try #require(RewardPointType("Game Rewards - SFS")), name: "Champion", summary: "")
    }

    @Test("The lists are read again after 30 days")
    func growsStaleAfterThirtyDays() throws {
        let catalog = RewardCatalog(offers: [try offer()], fetchedAt: read)
        #expect(!catalog.isStale(at: read.addingTimeInterval(29 * day)))
        #expect(catalog.isStale(at: read.addingTimeInterval(31 * day)))
    }

    @Test("A reading that found no list is tried again after a day")
    func anEmptyReadingGrowsStaleAfterADay() {
        let catalog = RewardCatalog(offers: [], fetchedAt: read)
        #expect(!catalog.isStale(at: read.addingTimeInterval(day / 2)))
        #expect(catalog.isStale(at: read.addingTimeInterval(2 * day)))
    }

    @Test("The file repository keeps the lists, and signing out leaves them")
    func theFileRepositoryKeepsTheLists() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("chronicle-keeper-rewards-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileCharacterRepository(folder: folder)
        #expect(try repository.loadRewardCatalog() == nil)
        let catalog = RewardCatalog(offers: [try offer()], fetchedAt: read)
        try repository.saveRewardCatalog(catalog)
        try repository.deleteSnapshot()
        #expect(try repository.loadRewardCatalog() == catalog)
    }

    @Test("The in-memory repository keeps the lists")
    func theInMemoryRepositoryKeepsTheLists() throws {
        let repository = InMemoryCharacterRepository()
        #expect(try repository.loadRewardCatalog() == nil)
        let catalog = RewardCatalog(offers: [try offer()], fetchedAt: read)
        try repository.saveRewardCatalog(catalog)
        #expect(try repository.loadRewardCatalog() == catalog)
    }
}

@Suite("Reading the reward lists from paizo.com")
struct RewardCatalogClientTests {
    private func stub() throws -> StubHTTPClient {
        let stub = StubHTTPClient()
        let boons = try Fixture.text("boons")
        stub.on("myAccount/rewards") { page(boons) }
        for (element, fixture) in [
            ("Rewards.1.", "reward-list-chronicle-pfs2-ajax"), ("Rewards.2.", "reward-list-game-pfs2-ajax"),
            ("Rewards.4.", "reward-list-chronicle-sfs-ajax"), ("Rewards.5.", "reward-list-game-sfs-ajax")
        ] {
            let answer = try Fixture.text(fixture)
            stub.on(element) { page(answer) }
        }
        return stub
    }

    @Test("Each free list is opened and read, in the page's order")
    func readsEveryFreeList() async throws {
        let stub = try stub()
        let client = OrganizedPlayClient(http: stub, credentials: InMemoryCredentialStore())
        let catalog = try await client.rewardCatalog()
        #expect(catalog.offers.count == 17)
        #expect(catalog.offers.first?.name == "PFS (2ed) Scenario #1–04: Bandits of Immenwood Boon A")
        #expect(catalog.offers.last?.name == "Acquisitives Champion")
    }

    @Test("The lists are only ever asked for: every request is a GET, sent as the page's script sends it")
    func onlyReads() async throws {
        let stub = try stub()
        let client = OrganizedPlayClient(http: stub, credentials: InMemoryCredentialStore())
        _ = try await client.rewardCatalog()
        let requests = stub.sentRequests
        #expect(requests.count == 5)
        let methods = Set(requests.map { $0.httpMethod ?? "GET" })
        #expect(methods == ["GET"])
        #expect(requests.allSatisfy { $0.httpBody == nil })
        let opened = Array(requests.dropFirst())
        let headers = Set(opened.map { $0.value(forHTTPHeaderField: "X-Requested-With") ?? "" })
        #expect(headers == ["XMLHttpRequest"])
        let firstQuery = opened.first?.url?.query ?? ""
        #expect(firstQuery.hasPrefix("_u=_1&"))
        let addresses = requests.map { $0.url?.absoluteString ?? "" }
        #expect(!addresses.contains { $0.contains("Rewards.0.") })
    }

    @Test("A list that doesn't open to a table fails the reading, naming the list")
    func aListThatDoesNotOpenFails() async throws {
        let stub = try stub()
        stub.on("Rewards.4.") { page("<p>Something else</p>") }
        let client = OrganizedPlayClient(http: stub, credentials: InMemoryCredentialStore())
        await #expect(throws: ParsingError(
            operation: "Reading the list of Chronicle Boons - SFS", reason: "the list has no table of rewards")
        ) {
            try await client.rewardCatalog()
        }
    }
}
