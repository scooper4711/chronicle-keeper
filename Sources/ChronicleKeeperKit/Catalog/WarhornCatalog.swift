import Foundation

/// Where "Who can play…?" looks up the adventures Paizo has published.
public protocol AdventureSearching: Sendable {
    /// The published adventures of these campaigns whose code or title contains the text.
    func adventures(matching text: String, in campaigns: [Campaign]) async throws -> AdventureSearchResults
}

public struct AdventureSearchResults: Hashable, Sendable {
    public var adventures: [AdventureEntry]
    /// False when the catalog had more matches than the search read.
    public var isComplete: Bool

    public static let none = AdventureSearchResults(adventures: [], isComplete: true)

    public init(adventures: [AdventureEntry], isComplete: Bool) {
        self.adventures = adventures
        self.isComplete = isComplete
    }
}

/// Searches Warhorn's catalog of scenarios (warhorn.net), which lists every Organized Play adventure with its
/// levels, tags and cover. Only the text being searched for is sent.
public struct WarhornCatalog: AdventureSearching {
    static let operation = "Searching Warhorn's catalog"
    static let pageSize = 100
    /// The pages one search reads at most. Warhorn answers with other games' scenarios and events' own entries
    /// too, a hundred to a page in the order of their names, so the adventures behind a common word such as
    /// "dragon" come after a dozen pages of them. Warhorn allows an address 300 requests in five minutes.
    static let longestSearch = 15
    /// A shorter text that isn't a number matches too much to be worth asking for.
    static let shortestText = 3
    // swiftlint:disable:next force_unwrapping
    static let endpoint = URL(string: "https://warhorn.net/graphql")!

    private let http: any HTTPClient

    public init(http: any HTTPClient) {
        self.http = http
    }

    public func adventures(matching text: String, in campaigns: [Campaign]) async throws -> AdventureSearchResults {
        let published = campaigns.filter(WarhornScenario.campaigns.values.contains)
        let texts = Self.searchTexts(for: text, campaigns: published)
        let found = try await withThrowingTaskGroup(of: AdventureSearchResults.self) { group in
            for text in texts {
                group.addTask { try await matches(of: text, in: published) }
            }
            return try await group.reduce(into: AdventureSearchResults.none) { all, some in
                all.adventures += some.adventures
                all.isComplete = all.isComplete && some.isComplete
            }
        }
        let adventures = AdventureCatalog.merged(published: found.adventures, own: [])
        return AdventureSearchResults(adventures: adventures, isComplete: found.isComplete)
    }

    /// What to ask Warhorn for. It names a scenario "PFS2 6-04: An Enkindled Carnival", so a number is asked for
    /// under each campaign's code: "6-0" alone is in thousands of names, "PFS2 6-0" in a few dozen.
    static func searchTexts(for text: String, campaigns: [Campaign]) -> [String] {
        let needle = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "–", with: "-")
        let number = needle.hasPrefix("#") ? String(needle.dropFirst()) : needle
        if number.firstMatch(of: numberPattern) != nil {
            return campaigns.map { "\($0.shortName) \(number)" }
        }
        return needle.count >= shortestText && !campaigns.isEmpty ? [needle] : []
    }

    private func matches(of text: String, in campaigns: [Campaign]) async throws -> AdventureSearchResults {
        var adventures: [AdventureEntry] = []
        var cursor: String?
        for _ in 0..<Self.longestSearch {
            let page = try await page(of: text, after: cursor)
            adventures += page.scenarios.compactMap(\.adventure)
                .filter { campaigns.contains($0.campaign) }
                .map(AdventureEntry.init(published:))
            guard let next = page.nextCursor else {
                return AdventureSearchResults(adventures: adventures, isComplete: true)
            }
            cursor = next
        }
        return AdventureSearchResults(adventures: adventures, isComplete: false)
    }

    private func page(of text: String, after cursor: String?) async throws -> WarhornPage {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(WarhornQuery(text: text, after: cursor))
        let response = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw ParsingError(operation: Self.operation, reason: Self.reason(forStatus: response.statusCode))
        }
        return try WarhornPage(reply: response.data)
    }

    private static func reason(forStatus status: Int) -> String {
        status == 429
            ? "Warhorn is asking the app to slow down for a few minutes"
            : "Warhorn answered with HTTP \(status)"
    }

    // Regex is not Sendable, but this literal is never mutated, so sharing it is safe.

    /// A season and a dash, as in "6-", "6-04" or "10-1".
    nonisolated(unsafe) private static let numberPattern = /^\d+-/
}

/// What to tell the player when the published adventures can't be searched. Their own adventures still are.
public enum AdventureSearchFailure {
    public static func text(for error: Error) -> String {
        if let urlError = error as? URLError, offlineCodes.contains(urlError.code) {
            return "You are not connected to the internet, so only your own adventures are listed."
        }
        let detail = (error as? ParsingError)?.reason ?? error.localizedDescription
        return "The published adventures couldn't be searched (\(detail)), so only your own are listed."
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff
    ]
}
