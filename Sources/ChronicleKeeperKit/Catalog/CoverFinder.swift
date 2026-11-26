import Foundation

/// Finds the cover of an adventure a session played: in the table the app ships with for an adventure that has no
/// number, and in the catalog "Who can play…?" searches for one that has.
public struct CoverFinder: Sendable {
    private let search: any AdventureSearching
    private let table: CoverTable

    public init(search: any AdventureSearching, table: CoverTable = .bundled) {
        self.search = search
        self.table = table
    }

    /// The cover, or nothing when neither the table nor the catalog lists the adventure with one. Only a numbered
    /// adventure is asked for, by its number.
    public func cover(of adventure: AdventureEntry) async throws -> URL? {
        let number = Self.searchText(for: adventure)
        guard !number.isEmpty else { return table.cover(of: adventure) }
        let found = try await search.adventures(matching: number, in: [adventure.campaign])
        return found.adventures.first(where: adventure.isSameAdventure)?.coverArt
    }

    /// The published adventure with this number, as the catalog names it, with its levels and cover; nothing when
    /// the catalog doesn't list it. For a chronicle sheet whose session paizo.com doesn't list yet (R1.14).
    public func adventure(code: String, in campaign: Campaign) async throws -> AdventureEntry? {
        let title = AdventureClassifier.title(forCode: code)
        let wanted = AdventureEntry(
            reference: AdventureReference(productID: "", title: title, summary: ""), campaign: campaign)
        let number = Self.searchText(for: wanted)
        guard !number.isEmpty else { return nil }
        return try await search.adventures(matching: number, in: [campaign]).adventures
            .first(where: wanted.isSameAdventure)
    }

    /// The covers of these adventures by ID, looked up one after another until the task is canceled or the catalog
    /// can't be reached. A cover is decoration: the ones not found wait for another time, and nobody is told.
    public func covers(of adventures: [AdventureEntry]) async -> [String: URL] {
        var found: [String: URL] = [:]
        for adventure in adventures where !Task.isCancelled {
            do {
                if let cover = try await cover(of: adventure) { found[adventure.id] = cover }
            } catch {
                break
            }
        }
        return found
    }

    /// The number that finds the adventure in the catalog ("6-04", "Bounty 14", "Quest (Series 2) #14"), or
    /// nothing for an adventure without one. The event a session was played at is no part of it.
    static func searchText(for adventure: AdventureEntry) -> String {
        if adventure.code.firstMatch(of: seasonCodePattern) != nil || adventure.code.hasPrefix("Bounty") {
            return adventure.code
        }
        let quest = AdventureTitle.withoutEvent(adventure.title).firstMatch(of: AdventureClassifier.questPattern)
        return quest.map { String($0.0) } ?? ""
    }

    // Regex is not Sendable, but this literal is never mutated, so sharing it is safe.

    nonisolated(unsafe) private static let seasonCodePattern = /^\d+-\d+$/
}
