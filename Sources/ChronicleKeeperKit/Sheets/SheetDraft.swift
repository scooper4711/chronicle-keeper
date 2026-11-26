import Foundation

/// The confirmation's three fields as the user sees and edits them (R1.11): text, filled with what was read and
/// empty where nothing was. An empty field is a value left unread, which changes nothing in the app.
public struct SheetDraft: Hashable, Sendable {
    /// "123456-2001", or only the part after the dash.
    public var characterNumber: String
    public var xp: String
    /// Gold or credits, written as the ledger writes them.
    public var funds: String

    public init(reading: SheetReading, currency: Currency) {
        let player = reading.playerNumber ?? ""
        let part = reading.characterPart ?? ""
        characterNumber = player.isEmpty ? part : "\(player)-\(part)"
        xp = reading.xp.map(XPText.of) ?? ""
        funds = reading.funds.map { Money.format($0, in: currency) } ?? ""
    }

    public subscript(field: SheetField) -> String {
        get {
            switch field {
            case .characterNumber: characterNumber
            case .xp: xp
            case .funds: funds
            }
        }
        set {
            switch field {
            case .characterNumber: characterNumber = newValue
            case .xp: xp = newValue
            case .funds: funds = newValue
            }
        }
    }

    /// The fields holding text that isn't a value: the sheet can't be kept until they are corrected or emptied.
    public func unreadableFields(in currency: Currency) -> Set<SheetField> {
        var fields: Set<SheetField> = []
        if numberParts == nil { fields.insert(.characterNumber) }
        if !Self.isEmpty(xp), xpValue == nil { fields.insert(.xp) }
        if !Self.isEmpty(funds), fundsValue(in: currency) == nil { fields.insert(.funds) }
        return fields
    }

    /// What was read, with the three fields as the user left them. A field that can't be read counts as empty.
    public func reading(correcting read: SheetReading, currency: Currency) -> SheetReading {
        var reading = read
        (reading.playerNumber, reading.characterPart) = numberParts ?? (nil, nil)
        reading.xp = xpValue
        reading.funds = fundsValue(in: currency)
        return reading
    }

    /// Takes the fields of a sheet read again (after turning the page), except where the user has typed something
    /// else than what was read before.
    public mutating func refill(from fresh: SheetDraft, replacing earlier: SheetDraft) {
        for field in SheetField.allCases where self[field] == earlier[field] {
            self[field] = fresh[field]
        }
    }

    // MARK: - Values

    private var xpValue: Double? { SheetNumber.xp(xp) }

    private func fundsValue(in currency: Currency) -> Int? {
        Money.parse(funds, in: currency)
    }

    /// The two parts of the character number; both nil for an empty field, and nil when the text isn't a number.
    /// One number alone is the character's part when it follows a dash or is short enough to be one, otherwise
    /// the Organized Play number.
    private var numberParts: (player: String?, part: String?)? {
        let text = characterNumber.trimmingCharacters(in: .whitespaces)
        guard text.allSatisfy({ ($0.isASCII && $0.isNumber) || " -–".contains($0) }) else { return nil }
        let runs = SheetNumber.digitRuns(in: text)
        switch runs.count {
        case 0: return text.isEmpty ? (nil, nil) : nil
        case 1: return Self.isPart(runs[0], in: text) ? (nil, runs[0]) : (runs[0], nil)
        case 2: return (runs[0], runs[1])
        default: return nil
        }
    }

    private static func isPart(_ run: String, in text: String) -> Bool {
        let followsADash = text.first.map { "-–".contains($0) } ?? false
        return followsADash || (run.count <= longestPart && text == run)
    }

    /// A character's own part of the number has at most four digits: "701", "2001".
    private static let longestPart = 4

    private static func isEmpty(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
