import Foundation
import Testing
@testable import ChronicleKeeperKit

@MainActor
struct StoredCoverTests {
    private let session = SessionFactory.session()

    /// A snapshot with the factory's session and one of an adventure the catalog doesn't have.
    private func snapshot() -> AccountSnapshot {
        let base = SnapshotFactory.snapshot()
        let unlisted = SessionFactory.session(title: "#9-99: Unlisted", sessionNumber: 2)
        return AccountSnapshot(
            characters: base.characters, sessions: base.sessions + [unlisted], fetchedAt: base.fetchedAt)
    }

    private func store(_ repository: InMemoryCharacterRepository = InMemoryCharacterRepository()) -> CharacterStore {
        let fresh = snapshot()
        return CharacterStore(repository: repository) { fresh }
    }

    @Test func aRefreshLooksCoversUpAndSavesThemWithTheAccount() async throws {
        let repository = InMemoryCharacterRepository()
        let store = store(repository)
        let search = StubSearch(Covers.catalog)
        await store.useCoverFinder(CoverFinder(search: search))
        #expect(search.questions.isEmpty)
        await store.refresh()
        await store.waitForCovers()
        #expect(store.cover(of: session) == Covers.carnival)
        #expect(Set(search.questions) == ["6-04", "9-99"])
        #expect(try repository.loadSnapshot()?.covers == store.covers)
        #expect(store.covers.count == 1)
    }

    @Test func aLaterRefreshKeepsTheCoversAndAsksOnlyForTheMissingOnes() async throws {
        let store = store()
        let search = StubSearch(Covers.catalog)
        await store.useCoverFinder(CoverFinder(search: search))
        await store.refresh()
        await store.waitForCovers()
        await store.refresh()
        await store.waitForCovers()
        #expect(store.cover(of: session) == Covers.carnival)
        #expect(search.questions.sorted() == ["6-04", "9-99", "9-99"])
    }

    @Test func coversAreLookedUpForTheAccountAlreadySaved() async throws {
        let repository = InMemoryCharacterRepository()
        try repository.saveSnapshot(snapshot())
        let store = store(repository)
        store.load()
        #expect(store.cover(of: session) == nil)
        await store.useCoverFinder(CoverFinder(search: StubSearch(Covers.catalog)))
        #expect(store.cover(of: session) == Covers.carnival)
        #expect(try repository.loadSnapshot()?.covers.count == 1)
    }

    @Test func anUnreachableCatalogLeavesTheAccountAsItIsWithoutAMessage() async throws {
        let repository = InMemoryCharacterRepository()
        let store = store(repository)
        let search = StubSearch(failure: URLError(.notConnectedToInternet))
        await store.useCoverFinder(CoverFinder(search: search))
        await store.refresh()
        await store.waitForCovers()
        #expect(store.covers.isEmpty)
        #expect(store.errorMessage == nil)
        #expect(store.roster.characters.count == 1)
        #expect(search.questions.count == 1)
    }

    @Test func aRefreshDoesNotWaitForTheCovers() async throws {
        let store = store()
        let search = HeldSearch()
        await store.useCoverFinder(CoverFinder(search: search))
        await store.refresh()
        #expect(store.roster.characters.count == 1)
        #expect(store.covers.isEmpty)
        search.release()
        await store.waitForCovers()
        #expect(store.cover(of: session) == Covers.carnival)
    }

    @Test func signingOutStopsThePassAndKeepsNothing() async throws {
        let repository = InMemoryCharacterRepository()
        let store = store(repository)
        let search = HeldSearch()
        await store.useCoverFinder(CoverFinder(search: search))
        await store.refresh()
        let pass = try #require(store.coverPass)
        store.signOut()
        search.release()
        await pass.value
        #expect(store.covers.isEmpty)
        #expect(try repository.loadSnapshot() == nil)
    }

    @Test func coversFoundWhileTheAccountIsLoadedAgainAreKept() async throws {
        let repository = InMemoryCharacterRepository()
        let store = store(repository)
        let search = HeldSearch()
        await store.useCoverFinder(CoverFinder(search: search))
        await store.refresh()
        store.load()
        search.release()
        await store.waitForCovers()
        #expect(store.cover(of: session) == Covers.carnival)
        #expect(try repository.loadSnapshot()?.covers == store.covers)
    }

    @Test func aLongHistoryIsLookedUpAFewAtATime() async throws {
        let base = SnapshotFactory.snapshot()
        let sessions = (1...CharacterStore.coversPerPass + 5).map {
            SessionFactory.session(title: "#9-\($0): Unlisted", sessionNumber: $0)
        }
        let long = AccountSnapshot(characters: base.characters, sessions: sessions, fetchedAt: base.fetchedAt)
        let store = CharacterStore(repository: InMemoryCharacterRepository()) { long }
        let search = StubSearch(Covers.catalog)
        await store.useCoverFinder(CoverFinder(search: search))
        await store.refresh()
        await store.waitForCovers()
        #expect(search.questions.count == CharacterStore.coversPerPass)
    }

    @Test func withoutAFinderOrAfterSigningOutThereAreNoCovers() async throws {
        let plain = store()
        await plain.refresh()
        await plain.waitForCovers()
        #expect(plain.covers.isEmpty)
        let store = store()
        await store.useCoverFinder(CoverFinder(search: StubSearch(Covers.catalog)))
        await store.refresh()
        await store.waitForCovers()
        store.signOut()
        #expect(store.covers.isEmpty)
        #expect(store.cover(of: session) == nil)
    }

    @Test func anAccountSavedBeforeCoversReadsAsHavingNone() throws {
        let saved = Data(#"{"characters":[],"sessions":[],"fetchedAt":"2026-11-01T10:00:00Z"}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(AccountSnapshot.self, from: saved).covers.isEmpty)
    }

    @Test func theSessionLooksCoversUpForTheUsersOwnAccount() async throws {
        let repository = InMemoryCharacterRepository()
        try repository.saveSnapshot(snapshot())
        let credentials = InMemoryCredentialStore()
        let live = AccountSession.LiveAccount(
            client: OrganizedPlayClient(http: StubHTTPClient(), credentials: credentials),
            credentials: credentials, repository: repository)
        let account = AccountSession(live: live)
        await account.startCovers(search: StubSearch(Covers.catalog))
        #expect(account.liveStore.cover(of: session) == Covers.carnival)
    }
}
