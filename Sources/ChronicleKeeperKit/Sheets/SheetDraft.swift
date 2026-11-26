import Foundation

/// The confirmation's fields as the user sees and edits them (R1.11): text, filled with what was read and empty
/// where nothing was. An empty field is a value left unread, which changes nothing in the app. A sheet added ahead
/// of its report also has its scenario number and the day it was played, which make its session (R1.14).
public struct SheetDraft: Hashable, Sendable {
    /// "123456-2001", or only the part after the dash.
    public var characterNumber: String
    public var xp: String
    /// Gold or credits, written as the ledger writes them.
    public var funds: String
    /// The scenario number: "6-04", "Quest 14", "Bounty 19".
    public var code: String
    /// The day played, for a sheet added ahead of its report; nil for a reported session's sheet, whose day
    /// paizo.com gives.
    public var day: Date?

    public init(reading: SheetReading, currency: Currency) {
        let player = reading.playerNumber ?? ""
        let part = reading.characterPart ?? ""
        characterNumber = player.isEmpty ? part : "\(player)-\(part)"
        xp = reading.xp.map(XPText.of) ?? ""
        funds = reading.funds.map { Money.format($0, in: currency) } ?? ""
        code = reading.code ?? ""
    }

    public subscript(field: SheetField) -> String {
        get {
            switch field {
            case .characterNumber: characterNumber
            case .xp: xp
            case .funds: funds
            case .code: code
            }
        }
        set {
            switch field {
            case .characterNumber: characterNumber = newValue
            case .xp: xp = newValue
            case .funds: funds = newValue
            case .code: code = newValue
            }
        }
    }

    /// The fields holding text that isn't a value: the sheet can't be kept until they are corrected or emptied.
    public func unreadableFields(in currency: Currency) -> Set<SheetField> {
        var fields: Set<SheetField> = []
        if numberParts == nil { fields.insert(.characterNumber) }
        if !Self.isEmpty(xp), xpValue == nil { fields.insert(.xp) }
        if !Self.isEmpty(funds), fundsValue(in: currency) == nil { fields.insert(.funds) }
        if !Self.isEmpty(code), codeValue == nil { fields.insert(.code) }
        return fields
    }

    /// Whether the scenario number is filled in, which a sheet added ahead of its report can't do without.
    public var hasCode: Bool { codeValue != nil }

    /// What was read, with the fields as the user left them. A field that can't be read counts as empty.
    public func reading(correcting read: SheetReading, currency: Currency) -> SheetReading {
        var reading = read
        (reading.playerNumber, reading.characterPart) = numberParts ?? (nil, nil)
        reading.xp = xpValue
        reading.funds = fundsValue(in: currency)
        // The number is asked for only on a sheet added ahead of its report; an empty field leaves what was read.
        if let codeValue { reading.code = codeValue }
        if let day { reading.playedOn = SheetDay.text(of: day) }
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

    private var codeValue: String? { AdventureClassifier.code(typed: code) }

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

extension SheetReading {
    /// What was read, on one line: "4 XP · 11.2 gp · character 123456-2001", with only the values that were read.
    public func summary(in currency: Currency) -> String {
        let number = [playerNumber, characterPart].compactMap { $0 }.joined(separator: "-")
        let parts = [
            xp.map { "\(XPText.of($0)) XP" }, funds.map { Money.format($0, in: currency) },
            number.isEmpty ? nil : "character \(number)"
        ].compactMap { $0 }
        return parts.isEmpty ? "nothing could be read for certain" : parts.joined(separator: " · ")
    }
}
