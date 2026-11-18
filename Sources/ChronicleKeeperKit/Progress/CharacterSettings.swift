import Foundation

/// What the user has told the app about a character; kept apart from what the site says.
public struct CharacterSettings: Hashable, Codable, Sendable {
    /// The track for sessions whose track can't be inferred.
    public var defaultTrack: Track
    /// The level the character began play at (1, 3, 5 or 7 in second edition campaigns); it can't change later.
    public var startingLevel: Int
    /// Corrections keyed by `PlayedSession.id`.
    public var overrides: [String: SessionOverride]
    public var notes: String
    /// The portrait's file name in the Portraits folder, or empty when the character has none.
    public var portraitFileName: String
    /// A link to the character's sheet (Pathbuilder, Demiplane, Foundry, a PDF…), or empty.
    public var characterSheetLink: String

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
