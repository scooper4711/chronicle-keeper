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
