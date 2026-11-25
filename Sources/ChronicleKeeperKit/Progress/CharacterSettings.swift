import Foundation

/// What the user has told the app about a character; kept apart from what the site says.
public struct CharacterSettings: Hashable, Codable, Sendable {
    /// The track for sessions whose track can't be inferred.
    public var defaultTrack: Track
    /// The level the character began play at (1, 3, 5 or 7 in second edition campaigns); it can't change later.
    public var startingLevel: Int
    /// Corrections keyed by `PlayedSession.keyWithinCharacter` and by `PlayedSession.id`, as 1.0.0 keyed them;
    /// read and write them with `override(for:)` and `setOverride(_:for:)`.
    public var overrides: [String: SessionOverride]
    public var notes: String
    /// The portrait's file name in the Portraits folder, or empty when the character has none.
    public var portraitFileName: String
    /// A link to the character's sheet (Pathbuilder, Demiplane, Foundry, a PDF…), or empty.
    public var characterSheetLink: String
    /// The gold and purchases ledger (R5). Kept out of the settings JSON on purpose (it isn't in `CodingKeys`): an
    /// older build rewrites that JSON with only the fields it knows, which would erase the ledger. It is saved in
    /// `wealth.json` and in the record's own `wealth` field instead (design.md, "The ledger's storage").
    public var wealth = CharacterWealth()

    public init(
        defaultTrack: Track = .normal, startingLevel: Int = 1,
        overrides: [String: SessionOverride] = [:], notes: String = ""
    ) {
        self.defaultTrack = defaultTrack
        self.startingLevel = startingLevel
        self.overrides = overrides
        self.notes = notes
        portraitFileName = ""
        characterSheetLink = ""
    }

    /// The character sheet link when it is a web address the app can open.
    public var characterSheetURL: URL? {
        guard let url = URL(string: characterSheetLink.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) else { return nil }
        return url
    }
}

extension CharacterSettings {
    /// The user's correction to a session. This version saves it under both the session's key and its ID (which
    /// has the character's name in it), so a device still on 1.0.0, which reads and writes only the ID, keeps
    /// working. When the two differ, the ID's was changed last, on such a device, so it wins. After that come ones
    /// 1.0.0 saved under a name the character no longer has, in a fixed order so the same one wins every time.
    public func override(for session: PlayedSession) -> SessionOverride? {
        overrides[session.id] ?? overrides[session.keyWithinCharacter] ?? olderOverride(for: session)
    }

    /// Saves the user's correction to a session under its key and its ID; nil removes it from both.
    public mutating func setOverride(_ override: SessionOverride?, for session: PlayedSession) {
        overrides[session.keyWithinCharacter] = override
        overrides[session.id] = override
    }

    private func olderOverride(for session: PlayedSession) -> SessionOverride? {
        let prefix = session.keyWithinCharacter + "#"
        return overrides.keys.filter { $0.hasPrefix(prefix) }.min().flatMap { overrides[$0] }
    }
}

extension CharacterSettings {
    /// `wealth` is left out on purpose; see its comment.
    private enum CodingKeys: String, CodingKey {
        case defaultTrack, startingLevel, overrides, notes, portraitFileName, characterSheetLink
    }

    /// Reads settings written by any version: a field an older version didn't have gets its default, so a record
    /// synced from another device or a file from an earlier release still opens.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            defaultTrack: try values.decodeIfPresent(Track.self, forKey: .defaultTrack) ?? .normal,
            startingLevel: try values.decodeIfPresent(Int.self, forKey: .startingLevel) ?? 1,
            overrides: try values.decodeIfPresent([String: SessionOverride].self, forKey: .overrides) ?? [:],
            notes: try values.decodeIfPresent(String.self, forKey: .notes) ?? "")
        portraitFileName = try values.decodeIfPresent(String.self, forKey: .portraitFileName) ?? ""
        characterSheetLink = try values.decodeIfPresent(String.self, forKey: .characterSheetLink) ?? ""
    }
}
