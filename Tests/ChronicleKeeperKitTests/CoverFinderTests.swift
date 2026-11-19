import Foundation
import Testing
@testable import ChronicleKeeperKit

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
