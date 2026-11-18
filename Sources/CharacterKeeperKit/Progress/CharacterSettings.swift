import Foundation

/// What the user has told the app about a character; kept apart from what the site says.
public struct CharacterSettings: Hashable, Codable, Sendable {
    /// The track for sessions whose track can't be inferred.
    public var defaultTrack: Track
    /// XP the site doesn't show, added to the sessions' total (may be negative).
    public var xpAdjustment: Double
    /// Corrections keyed by `PlayedSession.id`.
    public var overrides: [String: SessionOverride]
    public var notes: String
    /// The portrait's file name in the Portraits folder, or empty when the character has none.
    public var portraitFileName: String
    /// A link to the character's sheet (Pathbuilder, Demiplane, Foundry, a PDF…), or empty.
    public var characterSheetLink: String

    public init(
        defaultTrack: Track = .normal, xpAdjustment: Double = 0,
        overrides: [String: SessionOverride] = [:], notes: String = ""
    ) {
        self.defaultTrack = defaultTrack
        self.xpAdjustment = xpAdjustment
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
        case defaultTrack, xpAdjustment, overrides, notes, portraitFileName, characterSheetLink
    }

    /// Reads settings written by any version: a field an older version didn't have gets its default, so a record
    /// synced from another device or a file from an earlier release still opens.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            defaultTrack: try values.decodeIfPresent(Track.self, forKey: .defaultTrack) ?? .normal,
            xpAdjustment: try values.decodeIfPresent(Double.self, forKey: .xpAdjustment) ?? 0,
            overrides: try values.decodeIfPresent([String: SessionOverride].self, forKey: .overrides) ?? [:],
            notes: try values.decodeIfPresent(String.self, forKey: .notes) ?? "")
        portraitFileName = try values.decodeIfPresent(String.self, forKey: .portraitFileName) ?? ""
        characterSheetLink = try values.decodeIfPresent(String.self, forKey: .characterSheetLink) ?? ""
    }
}
