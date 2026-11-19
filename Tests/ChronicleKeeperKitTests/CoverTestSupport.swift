import Foundation
import Testing
@testable import ChronicleKeeperKit

/// A catalog that answers every search with the same adventures, and records what it was asked.
final class StubSearch: AdventureSearching, @unchecked Sendable {
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

/// A catalog whose answers wait until the test lets them through, to look at the store while a pass is under way.
final class HeldSearch: AdventureSearching, @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    private let answers = StubSearch(Covers.catalog)

    func adventures(matching text: String, in campaigns: [Campaign]) async throws -> AdventureSearchResults {
        await withCheckedContinuation { continuation in
            let isHeld = lock.withLock {
                if !isOpen { waiting.append(continuation) }
                return !isOpen
            }
            if !isHeld { continuation.resume() }
        }
        try Task.checkCancellation()
        return try await answers.adventures(matching: text, in: campaigns)
    }

    func release() {
        let held = lock.withLock {
            isOpen = true
            defer { waiting = [] }
            return waiting
        }
        held.forEach { $0.resume() }
    }
}

enum Covers {
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
