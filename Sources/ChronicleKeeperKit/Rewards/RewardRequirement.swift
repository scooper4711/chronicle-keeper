import Foundation

/// What a character must have done for a free reward, as far as the app can check it against the account.
public enum RewardRequirement: Hashable, Sendable {
    /// Played one of the adventures, or every one of them when `needsAll`.
    case played([RewardAdventure], needsAll: Bool)
    /// That much reputation with the faction, or with any faction when `faction` is empty.
    case reputation(points: Int, faction: String)
    /// Played that many sessions.
    case sessions(Int)
    /// A condition the account doesn't show, or a wording the app doesn't know. Never signaled.
    case unknown
}

/// An adventure a reward's condition names: by its code where the text has one ("6-03", "Quest 2"), and by the
/// spellings of its title to try against a session that has no code.
public struct RewardAdventure: Hashable, Sendable {
    public let code: String
    public let titles: [String]
    /// The titles' `AdventureTitle.nameKey`s, worked out once.
    let nameKeys: [String]

    public init(code: String = "", titles: [String]) {
        self.code = code
        self.titles = titles
        nameKeys = titles.map(AdventureTitle.nameKey).filter { !$0.isEmpty }
    }

    /// Whether a played adventure is this one: the same code when both have one, as `AdventureEntry` compares
    /// them, and otherwise the same name.
    func matches(_ played: PlayedAdventure) -> Bool {
        if !code.isEmpty, !played.code.isEmpty { return code == played.code }
        return nameKeys.contains { key in played.nameKeys.contains { AdventureTitle.isSameKey(key, $0) } }
    }
}

/// What a session's adventure is known by, worked out once per character: comparing is most of the work.
struct PlayedAdventure: Hashable, Sendable {
    let sessionID: String
    let title: String
    let code: String
    /// Of the whole title and of its core, so that an Adventure Path volume's own name, "The Seventh Arch", is
    /// found in "Pathfinder Adventure Path #187: The Seventh Arch (Gatewalkers 1 of 3)".
    let nameKeys: [String]

    init(_ progress: SessionProgress) {
        let adventure = progress.session.adventure
        sessionID = progress.id
        title = AdventureTitle.withoutEvent(adventure.title)
        code = AdventureClassifier.code(of: adventure) ?? ""
        let keys = [title, Self.core(of: title)].map(AdventureTitle.nameKey).filter { !$0.isEmpty }
        nameKeys = keys.first == keys.last ? Array(keys.prefix(1)) : keys
    }

    /// The title without what leads up to its first colon and without a parenthesis at its end.
    static func core(of title: String) -> String {
        let bare = title.replacing(trailingParenthesisPattern, with: "")
        guard let colon = bare.firstRange(of: ": ") else { return bare }
        return String(bare[colon.upperBound...])
    }

    // Regex is not Sendable, but this literal is never mutated, so sharing it is safe.
    nonisolated(unsafe) private static let trailingParenthesisPattern = /\s*\([^)]*\)\s*$/
}

/// The spelling of a reward's name that the lists and "Boons you have purchased" are compared by: the site writes
/// one adventure's boons "#1–01: … Boon A" with an en dash and "#1-01: … Boon B" with a hyphen.
enum RewardName {
    static func plain(_ text: String) -> String {
        text.replacing(dashPattern, with: "-").replacing(apostrophePattern, with: "'")
            .replacing(quotePattern, with: "\"")
    }

    /// For telling whether two names are one reward's.
    static func key(_ name: String) -> String {
        plain(name).lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The key an adventure's lettered boons share: "Boon A", "Boon B" and "Boon C" are alternatives, of which the
    /// Chronicle Sheet says which one was earned. A reward that isn't lettered has its own.
    static func choiceKey(_ name: String) -> String {
        key(withoutLetter(name))
    }

    static func withoutLetter(_ name: String) -> String {
        plain(name).replacing(letterPattern, with: "")
    }

    /// "Boon A" of a lettered boon's name, or an empty string.
    static func letter(of name: String) -> String {
        plain(name).firstMatch(of: letterPattern).map { String($0.0).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    // Regex is not Sendable, but these literals are never mutated, so sharing them is safe.
    nonisolated(unsafe) private static let dashPattern = /[–—]/
    nonisolated(unsafe) private static let apostrophePattern = /[’‘]/
    nonisolated(unsafe) private static let quotePattern = /[“”]/
    nonisolated(unsafe) private static let letterPattern = /\s+Boon [A-Z]\s*$/
}
