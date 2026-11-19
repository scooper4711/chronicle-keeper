import Foundation
import Testing
@testable import ChronicleKeeperKit

/// A catalog that answers every search with the same adventures, and records what it was asked.
private final class StubSearch: AdventureSearching, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [String] = []
    private let adventures: [AdventureEntry]
    private let failure: Error?

    init(_ adventures: [PublishedAdventure] = [], failure: Error? = nil) {
        self.adventures = adventures.map(AdventureEntry.init(published:))
        self.failure = failure
    }

    var questions: [String] { lock.withLock { asked } }

    func adventures(matching text: String, in campaigns: [Campaign]) async throws -> AdventureSearchResults {
        lock.withLock { asked.append(text) }
        if let failure { throw failure }
        return AdventureSearchResults(adventures: adventures, isComplete: true)
    }
}

private enum Covers {
    static let carnival = URL(string: "https://example.com/carnival.jpg")

    static func published(_ title: String, cover: URL? = nil) -> PublishedAdventure {
        var adventure = PublishedAdventure(campaign: .pathfinder2, title: title)
        adventure.coverArt = cover
        return adventure
    }

    static let enough = url("enough")
    static let upperLevel = url("upper-level")
    static let burntOfferings = url("burnt-offerings")
    static let skinsawMurders = url("skinsaw-murders")

    static func url(_ name: String) -> URL {
        URL(string: "https://example.com/\(name).jpg") ?? URL(fileURLWithPath: "/")
    }

    static func row(_ name: String, campaign: String = "PFS2", cover: URL) -> CoverTable.Row {
        CoverTable.Row(campaign: campaign, name: name, cover: cover)
    }

    static func firstEdition(_ name: String, cover: URL) -> CoverTable.Row {
        row(name, campaign: "PFS1", cover: cover)
    }

    /// A few of the shipped table's adventures, under the names Warhorn gives them.
    static var table: CoverTable {
        CoverTable(rows: [
            row("PFS2 7-01: Intro: Year of Battle’s Spark—Enough is Enough", cover: enough),
            row("PF2 Adventure: Menace Under Otari, Part 1: Upper Level (from PF2 Beginner Box)", cover: upperLevel),
            firstEdition("PF1 AP 001: Rise of the Runelords, Part 1: Burnt Offerings", cover: burntOfferings),
            firstEdition("PF1 AP 002: Rise of the Runelords, Part 2: The Skinsaw Murders", cover: skinsawMurders),
            // The same name under a campaign the app doesn't follow, which the table leaves out.
            row("Adventure: Menace Under Otari", campaign: "DDAL", cover: url("another-campaign"))
        ])
    }

    static func played(_ title: String, in campaign: Campaign = .pathfinder2) -> AdventureEntry {
        AdventureEntry(reference: AdventureReference(productID: "", title: title, summary: ""), campaign: campaign)
    }

    /// The catalog has the factory session's adventure with a cover, and another without one.
    static var catalog: [PublishedAdventure] {
        [published("#6-05: Another"), published("#6-04: An Enkindled Carnival", cover: carnival)]
    }
}

struct CoverFinderTests {
    private static let kingInThorns = "#2-00: The King in Thorns - [PaizoCon 2024] PFS(2ed) #2-00: The King in Thorns"
    private static let enoughAtPaizoCon =
        "Intro: Enough is Enough - [PaizoCon Online 2025] PFS(2ed) Intro: Enough is Enough"

    @Test(arguments: [
        ("#6-04: An Enkindled Carnival", "6-04"),
        (kingInThorns, "2-00"),
        ("Pathfinder Bounty #14: The Blackwood Truce", "Bounty 14"),
        ("Pathfinder Quest (Series 2) #14: The Swordlord’s Challenge", "Quest (Series 2) #14"),
        ("Quest #1: The Sandstone Secret", "Quest #1"),
        ("Quest #1: The Sandstone Secret - [Con #7] PFS(2ed) Quest #1: The Sandstone Secret", "Quest #1"),
        ("Intro: Year of Immortal Influence", ""),
        ("Intro #2: United in Purpose", ""),
        ("Starfinder Free RPG Day: Battle for Nova Rush", ""),
        (enoughAtPaizoCon, ""),
        ("Quest for the Frozen Flame - [Con #7] PFS(2ed) Quest for the Frozen Flame", ""),
        ("Pathfinder Society Scenario", "")
    ])
    func asksOnlyForAnAdventuresNumber(title: String, text: String) {
        let adventure = SessionFactory.session(title: title, summary: "").adventureEntry
        #expect(CoverFinder.searchText(for: adventure) == text)
    }

    @Test func anAdventureWithoutANumberGetsItsCoverFromTheTableAndAsksNobody() async throws {
        let search = StubSearch(Covers.catalog)
        let finder = CoverFinder(search: search, table: Covers.table)
        let played = SessionFactory.session(title: Self.enoughAtPaizoCon, summary: "").adventureEntry
        #expect(try await finder.cover(of: played) == Covers.enough)
        #expect(search.questions.isEmpty)
    }

    @Test func aNumberedAdventureIsAskedForEvenWhenTheTableHasItsName() async throws {
        let search = StubSearch(Covers.catalog)
        let table = CoverTable(rows: [Covers.row("PFS2 6-04: An Enkindled Carnival", cover: Covers.enough)])
        let finder = CoverFinder(search: search, table: table)
        #expect(try await finder.cover(of: SessionFactory.session().adventureEntry) == Covers.carnival)
        #expect(search.questions == ["6-04"])
    }

    @Test func findsTheCoverOfTheSameAdventure() async throws {
        let search = StubSearch(Covers.catalog)
        let cover = try await CoverFinder(search: search).cover(of: SessionFactory.session().adventureEntry)
        #expect(cover == Covers.carnival)
        #expect(search.questions == ["6-04"])
    }

    @Test func findsNothingForAnAdventureTheCatalogLacksOrHasNoCoverFor() async throws {
        let finder = CoverFinder(search: StubSearch(Covers.catalog))
        let unlisted = SessionFactory.session(title: "#9-99: Unlisted").adventureEntry
        let coverless = SessionFactory.session(title: "#6-05: Another").adventureEntry
        #expect(try await finder.cover(of: unlisted) == nil)
        #expect(try await finder.cover(of: coverless) == nil)
    }

    @Test func asksNothingForATitleWithNoName() async throws {
        let search = StubSearch(Covers.catalog)
        let nameless = SessionFactory.session(title: "Pathfinder Society Scenario", summary: "").adventureEntry
        #expect(try await CoverFinder(search: search).cover(of: nameless) == nil)
        #expect(search.questions.isEmpty)
    }

    @Test func aSessionsCatalogEntryCarriesItsSavedCover() throws {
        let session = SessionFactory.session()
        let cover = try #require(Covers.carnival)
        let catalog = AdventureCatalog(sessions: [session], covers: [session.adventureEntry.id: cover])
        #expect(catalog.entries.map(\.coverArt) == [cover])
        #expect(AdventureCatalog(sessions: [session]).entries.map(\.coverArt) == [nil])
    }
}

struct CoverTableTests {
    private static let lowerDungeon =
        "Pathfinder Beginner Box (Remastered Edition) - Pathfinder Beginner Box: Menace Under Otari - Lower Dungeon"

    @Test func theSameNameFindsTheCoverHoweverItIsSpelled() {
        let played = Covers.played("Intro to the Year of Battle’s Spark—Enough is Enough")
        #expect(Covers.table.cover(of: played) == Covers.enough)
    }

    @Test func aPartOfTheNameFindsTheCoverOfAnAdventureNamedDifferently() {
        #expect(Covers.table.cover(of: Covers.played(Self.lowerDungeon)) == Covers.upperLevel)
    }

    @Test func aVolumeOfAnAdventurePathGetsItsOwnCover() {
        let second = "Pathfinder Adventure Path #2: The Skinsaw Murders (Rise of the Runelords 2 of 6)"
        let unlisted = "Pathfinder Adventure Path #7: Something Else (Rise of the Runelords 7 of 6)"
        #expect(Covers.table.cover(of: Covers.played(second, in: .pathfinder1)) == Covers.skinsawMurders)
        #expect(Covers.table.cover(of: Covers.played(unlisted, in: .pathfinder1)) == Covers.burntOfferings)
    }

    @Test func anotherCampaignsOrAnUnlikeAdventureHasNoCover() {
        #expect(Covers.table.cover(of: Covers.played(Self.lowerDungeon, in: .starfinder1)) == nil)
        #expect(Covers.table.cover(of: Covers.played("Pathfinder Adventure: Shadows at Sundown")) == nil)
        #expect(Covers.table.cover(of: Covers.played("Pathfinder Society Scenario")) == nil)
        #expect(CoverTable.empty.cover(of: Covers.played(Self.lowerDungeon)) == nil)
    }

    /// The titles of real sessions that have no number, which the shipped table has to know.
    @Test(arguments: [
        ("Intro #2: United in Purpose", Campaign.pathfinder2),
        ("Intro: Year of Boundless Wonder", .pathfinder2),
        ("Intro: Year of Immortal Influence", .pathfinder2),
        ("Intro to the Year of Battle’s Spark—Enough is Enough", .pathfinder2),
        (lowerDungeon, .pathfinder2),
        ("Starfinder Free RPG Day: Battle for Nova Rush", .starfinder2)
    ])
    func theShippedTableHasTheCoversOfUnnumberedSessions(title: String, campaign: Campaign) {
        #expect(!CoverTable.bundled.isEmpty)
        #expect(CoverTable.bundled.cover(of: Covers.played(title, in: campaign)) != nil)
    }
}

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
        await store.refresh()
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
        #expect(store.covers.isEmpty)
        #expect(store.errorMessage == nil)
        #expect(store.roster.characters.count == 1)
        #expect(search.questions.count == 1)
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
        #expect(search.questions.count == CharacterStore.coversPerPass)
    }

    @Test func withoutAFinderOrAfterSigningOutThereAreNoCovers() async throws {
        let plain = store()
        await plain.refresh()
        #expect(plain.covers.isEmpty)
        let store = store()
        await store.useCoverFinder(CoverFinder(search: StubSearch(Covers.catalog)))
        await store.refresh()
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
