import Foundation

/// A published adventure as a catalog names it, before the app works out its code and kind.
public struct PublishedAdventure: Hashable, Sendable {
    public let campaign: Campaign
    public let title: String
    public var levelRange: LevelRange?
    public var isRepeatable = false
    public var coverArt: URL?

    public init(campaign: Campaign, title: String) {
        self.campaign = campaign
        self.title = title
    }
}

/// An adventure a character might play.
public struct AdventureEntry: Hashable, Sendable, Identifiable {
    public let campaign: Campaign
    /// Paizo's product ID as a session links to it, or empty for an adventure known only from a catalog.
    public let productID: String
    /// "6-04", "Quest 15", "Bounty 19", or empty when the title has no number.
    public let code: String
    public let title: String
    public let kind: AdventureKind
    public let levelRange: LevelRange?
    public var isRepeatable: Bool
    /// Where the cover is, for an adventure a catalog knows or whose cover was looked up.
    public var coverArt: URL?

    /// The adventure's campaign with its code, or with its name when it has none.
    public var id: String { "\(campaign.shortName)|\(code.isEmpty ? AdventureTitle.nameKey(title) : code)" }

    public init(reference: AdventureReference, campaign: Campaign) {
        self.campaign = campaign
        productID = reference.productID
        code = AdventureClassifier.code(of: reference) ?? ""
        title = reference.title
        kind = AdventureClassifier.kind(of: reference)
        levelRange = AdventureClassifier.levelRange(of: reference)
        isRepeatable = kind.isRepeatable
        coverArt = nil
    }

    public init(published adventure: PublishedAdventure) {
        let reference = AdventureReference(productID: "", title: adventure.title, summary: "")
        campaign = adventure.campaign
        productID = ""
        code = AdventureClassifier.code(of: reference) ?? ""
        title = adventure.title
        kind = AdventureClassifier.kind(ofPublished: adventure.title)
        levelRange = adventure.levelRange
        isRepeatable = adventure.isRepeatable || kind.isRepeatable
        coverArt = adventure.coverArt
    }

    /// Whether a session was this adventure.
    public func matches(_ session: PlayedSession) -> Bool {
        isSameAdventure(as: session.adventureEntry)
    }

    /// The same product, or the same code in the same campaign, or the same name when either has no code: a
    /// catalog numbers some adventures that the Sessions tab only names, such as "Intro: Year of Boundless Wonder".
    public func isSameAdventure(as other: AdventureEntry) -> Bool {
        guard campaign == other.campaign else { return false }
        if !productID.isEmpty, productID == other.productID { return true }
        if !code.isEmpty, !other.code.isEmpty { return code == other.code }
        return AdventureTitle.isSameName(title, other.title)
    }
}

/// The adventures the player's sessions name, to which a search adds the published ones.
public struct AdventureCatalog: Sendable {
    public let entries: [AdventureEntry]

    /// `covers` are the ones saved with the account, by entry ID.
    public init(sessions: [PlayedSession], covers: [String: URL] = [:]) {
        let played = sessions.map { session in
            var entry = session.adventureEntry
            entry.coverArt = covers[entry.id]
            return entry
        }
        entries = Self.merged(published: [], own: played)
    }

    public init(roster: CharacterRoster, covers: [String: URL] = [:]) {
        self.init(sessions: roster.characters.flatMap { $0.sessions.map(\.session) }, covers: covers)
    }

    /// Entries whose title or code contains the text, in the given campaign or all of them.
    public func search(_ text: String, campaign: Campaign? = nil) -> [AdventureEntry] {
        let needle = text.trimmingCharacters(in: .whitespaces)
        return entries.filter { entry in
            (campaign == nil || entry.campaign == campaign)
                && (needle.isEmpty || entry.title.localizedCaseInsensitiveContains(needle)
                    || entry.code.localizedCaseInsensitiveContains(needle))
        }
    }

    /// One entry per adventure, in the list's order. A published adventure stands for the sessions that played it,
    /// as its title is spelled the same for everyone.
    public static func merged(published: [AdventureEntry], own: [AdventureEntry]) -> [AdventureEntry] {
        var kept: [AdventureEntry] = []
        for entry in published + own where !kept.contains(where: entry.isSameAdventure) {
            kept.append(entry)
        }
        return kept.sorted(by: isBefore)
    }

    /// By campaign, in the sidebar's order, then by title, numbers in order ("#6-04" before "#6-10").
    private static func isBefore(_ first: AdventureEntry, _ second: AdventureEntry) -> Bool {
        if first.campaign.sortOrder != second.campaign.sortOrder {
            return first.campaign.sortOrder < second.campaign.sortOrder
        }
        return first.title.localizedStandardCompare(second.title) == .orderedAscending
    }
}

extension PlayedSession {
    /// The adventure the session played, as "Who can play…?" lists it.
    public var adventureEntry: AdventureEntry { AdventureEntry(reference: adventure, campaign: campaign) }
}

/// Compares the names adventures go by, which the Sessions tab and a catalog spell differently.
public enum AdventureTitle {
    /// Whether two titles name one adventure: the same words, or one title's words inside the other's, as in
    /// "Adventure: Battle for Nova Rush" and "Starfinder Free RPG Day: Battle for Nova Rush". A short name has to
    /// match whole, so that "Abduction" isn't found inside a longer title.
    static func isSameName(_ first: String, _ second: String) -> Bool {
        isSameKey(nameKey(first), nameKey(second))
    }

    /// The same, for two titles' name keys.
    static func isSameKey(_ first: String, _ second: String) -> Bool {
        let keys = [first, second].sorted { $0.count < $1.count }
        guard !keys[0].isEmpty else { return false }
        return keys[0] == keys[1] || (keys[0].count >= shortestNameInsideAnother && keys[1].contains(keys[0]))
    }

    static let shortestNameInsideAnother = 12

    /// The words that name the adventure, run together: "Intro to the Year of Battle’s Spark" on the Sessions tab
    /// and "#7-01: Intro: Year of Battle's Spark" in a catalog both become "yearofbattlesspark".
    static func nameKey(_ title: String) -> String {
        let folded = withoutEvent(title).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacing(apostrophePattern, with: "")
            .replacing(seasonCodePattern, with: " ")
        let words = folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return words.filter { !fillerWords.contains($0) }.joined()
    }

    /// The title without the event it was played at. The Sessions tab titles a convention's session "#2-00: The
    /// King in Thorns - [PaizoCon 2024] PFS(2ed) #2-00: The King in Thorns"; the event is no part of the
    /// adventure's name, and is never sent to a catalog.
    static func withoutEvent(_ title: String) -> String {
        title.replacing(eventPattern, with: "")
    }

    /// Words that say what kind of product it is, or that one spelling has and another leaves out.
    static let fillerWords: Set<String> = [
        "pathfinder", "starfinder", "society", "scenario", "adventure", "intro", "to", "the",
        "pfs", "pfs1", "pfs2", "sfs", "sfs1", "sfs2", "2ed"
    ]

    // Regex is not Sendable, but these literals are never mutated, so sharing them is safe.

    nonisolated(unsafe) private static let apostrophePattern = /['’]/
    /// "#7-01" or "7–01": the number is compared as the code, not as part of the name.
    nonisolated(unsafe) private static let seasonCodePattern = /#?\d+[-–]\d+/
    /// " - [PaizoCon 2024] …" to the end of the title.
    nonisolated(unsafe) private static let eventPattern = /\s+-\s+\[.*$/
}
