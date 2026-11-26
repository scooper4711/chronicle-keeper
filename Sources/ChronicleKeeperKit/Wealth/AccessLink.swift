import Foundation

/// What the user says makes a marked purchase Society legal (R5.10): a boon or a Chronicle Sheet, of the buyer or of
/// another character in the same campaign. The app doesn't check that it grants the item: the user vouches for it.
/// The names are copied in, so the purchase reads the same offline and after paizo.com stops listing the source.
public struct AccessLink: Hashable, Codable, Sendable {
    /// What a purchase is linked to. Not an enum, so that a kind a newer version adds is kept as it was read: this
    /// version still reads the ledger, shows the link by the names copied into it, and writes it back unchanged.
    /// An enum would fail on it, and one unreadable link stops the whole character from syncing.
    public struct Kind: RawRepresentable, Hashable, Codable, Sendable {
        public static let boon = Kind(rawValue: "boon")
        public static let chronicle = Kind(rawValue: "chronicle")

        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    public var kind: Kind
    /// `Boon.id` for a boon; `chronicleID(characterNumber:sessionKey:)` for a Chronicle Sheet.
    public var sourceID: String
    /// The boon's name, or the adventure's title.
    public var sourceName: String
    /// The character the boon or the Chronicle Sheet belongs to.
    public var characterName: String
    /// Fields a newer version saved that this one doesn't know; written back as they were.
    public var unknownFields = UnknownFields()

    public init(kind: Kind, sourceID: String, sourceName: String, characterName: String) {
        self.kind = kind
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.characterName = characterName
    }

    public init(boon: Boon) {
        self.init(kind: .boon, sourceID: boon.id, sourceName: boon.name, characterName: boon.characterName)
    }

    /// The Chronicle Sheet of one of a character's sessions.
    public init(session: PlayedSession, of character: CharacterRecord) {
        self.init(
            kind: .chronicle,
            sourceID: Self.chronicleID(characterNumber: character.id, sessionKey: session.keyWithinCharacter),
            sourceName: session.adventure.title, characterName: character.name)
    }

    /// Names a session by its character's number, as the character's name can change on paizo.com.
    public static func chronicleID(characterNumber: String, sessionKey: String) -> String {
        "\(characterNumber)/\(sessionKey)"
    }

    /// Names the source among boons and Chronicle Sheets alike.
    public var key: String { "\(kind.rawValue):\(sourceID)" }

    /// "Korbul Thornbrook's boon Abendego's Cannon", or "…'s Chronicle Sheet for #6-00: Abendego's Cannon".
    /// A kind this version doesn't know is named only by what it copied in.
    public var sourceDescription: String {
        switch kind {
        case .boon: "\(characterName)'s boon \(sourceName)"
        case .chronicle: "\(characterName)'s Chronicle Sheet for \(sourceName)"
        default: "\(characterName)'s \(sourceName)"
        }
    }

    /// What the purchase's check is called: "Linked to a boon".
    public var linkedLabel: String {
        switch kind {
        case .boon: "Linked to a boon"
        case .chronicle: "Linked to a Chronicle Sheet"
        default: "Linked"
        }
    }

    /// The menu item that takes the link off: "Unlink Boon".
    public var unlinkTitle: String {
        switch kind {
        case .boon: "Unlink Boon"
        case .chronicle: "Unlink Chronicle Sheet"
        default: "Unlink"
        }
    }
}

extension AccessLink {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, sourceID, sourceName, characterName
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try values.decode(Kind.self, forKey: .kind),
            sourceID: try values.decode(String.self, forKey: .sourceID),
            sourceName: try values.decodeIfPresent(String.self, forKey: .sourceName) ?? "",
            characterName: try values.decodeIfPresent(String.self, forKey: .characterName) ?? "")
        unknownFields = try UnknownFields(from: decoder, known: Set(CodingKeys.allCases.map(\.stringValue)))
    }

    public func encode(to encoder: Encoder) throws {
        try unknownFields.encode(to: encoder)
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(kind, forKey: .kind)
        try values.encode(sourceID, forKey: .sourceID)
        try values.encode(sourceName, forKey: .sourceName)
        try values.encode(characterName, forKey: .characterName)
    }
}
