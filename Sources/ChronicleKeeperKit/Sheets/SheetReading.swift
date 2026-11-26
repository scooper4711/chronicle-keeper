import Foundation

/// What was read from a chronicle sheet (R1.10). Every field stands alone and is nil when it couldn't be read with
/// certainty: an unread field changes nothing in the app.
public struct SheetReading: Hashable, Codable, Sendable {
    /// Where the lines came from, which says how far they can be trusted.
    public enum Source: String, Hashable, Codable, Sendable {
        /// The PDF's own text: a sheet a program filled in. It can't be misread.
        case pdfText
        /// Text recognition on a picture of the sheet, handwriting included. It can be misread.
        case recognized
    }

    /// The adventure's code as `AdventureClassifier` gives it: "6-04", "Quest 14", "Bounty 19".
    public var code: String?
    /// The Organized Play number: the part of a character's number before the dash.
    public var playerNumber: String?
    /// The part of the character's number after the dash ("2001"), which says which of the player's characters.
    public var characterPart: String?
    public var xp: Double?
    /// The gold or credits gained, in copper.
    public var funds: Int?
    public var eventCode: String?
    public var source: Source
    /// The warnings about this sheet the user has cleared, by `SheetMismatch.id`.
    public var clearedWarnings: Set<String>
    /// Fields a newer version saved that this one doesn't know; written back as they were.
    public var unknownFields = UnknownFields()

    public init(source: Source = .pdfText) {
        self.source = source
        clearedWarnings = []
    }

    /// Whether nothing at all was read.
    public var isEmpty: Bool {
        code == nil && playerNumber == nil && characterPart == nil && xp == nil && funds == nil && eventCode == nil
    }
}

extension SheetReading {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case code, playerNumber, characterPart, xp, funds, eventCode, source, clearedWarnings
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        code = try values.decodeIfPresent(String.self, forKey: .code)
        playerNumber = try values.decodeIfPresent(String.self, forKey: .playerNumber)
        characterPart = try values.decodeIfPresent(String.self, forKey: .characterPart)
        xp = try values.decodeIfPresent(Double.self, forKey: .xp)
        funds = try values.decodeIfPresent(Int.self, forKey: .funds)
        eventCode = try values.decodeIfPresent(String.self, forKey: .eventCode)
        // A source a newer version names counts as the one that needs checking.
        let sourceName = try values.decodeIfPresent(String.self, forKey: .source) ?? ""
        source = Source(rawValue: sourceName) ?? .recognized
        clearedWarnings = try values.decodeIfPresent(Set<String>.self, forKey: .clearedWarnings) ?? []
        unknownFields = try UnknownFields(from: decoder, known: Set(CodingKeys.allCases.map(\.stringValue)))
    }

    public func encode(to encoder: Encoder) throws {
        try unknownFields.encode(to: encoder)
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(code, forKey: .code)
        try values.encodeIfPresent(playerNumber, forKey: .playerNumber)
        try values.encodeIfPresent(characterPart, forKey: .characterPart)
        try values.encodeIfPresent(xp, forKey: .xp)
        try values.encodeIfPresent(funds, forKey: .funds)
        try values.encodeIfPresent(eventCode, forKey: .eventCode)
        try values.encode(source, forKey: .source)
        try values.encode(clearedWarnings.sorted(), forKey: .clearedWarnings)
    }
}
