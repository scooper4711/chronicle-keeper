import Foundation

/// An adventure a character might play.
public struct AdventureEntry: Hashable, Codable, Sendable, Identifiable {
    public let campaign: Campaign
    public let productID: String
    /// "6-04", "Quest 15", "Bounty 19", or empty when the title has no number.
    public let code: String
    public let title: String
    public let kind: AdventureKind
    public let levelRange: LevelRange?
    public var isRepeatable: Bool

    public var id: String { productID.isEmpty ? "\(campaign.shortName)|\(title)" : productID }

    public init(reference: AdventureReference, campaign: Campaign) {
        self.campaign = campaign
        productID = reference.productID
        code = AdventureClassifier.code(of: reference) ?? ""
        title = reference.title
        kind = AdventureClassifier.kind(of: reference)
        levelRange = AdventureClassifier.levelRange(of: reference)
        isRepeatable = kind.isRepeatable
    }

    /// Whether a session was this adventure: the same product, or the same code in the same campaign.
    public func matches(_ session: PlayedSession) -> Bool {
        guard session.campaign == campaign else { return false }
        if !productID.isEmpty, productID == session.adventure.productID { return true }
        return !code.isEmpty && AdventureClassifier.code(of: session.adventure) == code
    }
}

/// The adventures the app knows, gathered from every session the player has.
public struct AdventureCatalog: Sendable {
    public let entries: [AdventureEntry]

    public init(sessions: [PlayedSession]) {
        var seen: [String: AdventureEntry] = [:]
        for session in sessions {
            let entry = AdventureEntry(reference: session.adventure, campaign: session.campaign)
            seen[entry.id] = seen[entry.id] ?? entry
        }
        entries = seen.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
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
}
