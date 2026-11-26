import CoreGraphics
import Foundation

/// Works out what a chronicle sheet says from its lines of text and where they are (R1.10): the adventure's code,
/// whose sheet it is, and the XP and gold it gave.
///
/// It never guesses. A value is read only when its label is on the sheet once, the sheet's format says which side
/// of the label the box is on, exactly one written line is in that box, and that line is a clean number. Anything
/// less leaves the field nil, and the app then behaves as it does without a sheet.
public enum SheetInterpreter {
    public static func reading(of lines: [RecognizedLine], source: SheetReading.Source) -> SheetReading {
        locatedReading(of: lines, source: source).reading
    }

    /// The reading with where on the page each value was found, for showing it to the user (R1.11).
    public static func locatedReading(of lines: [RecognizedLine], source: SheetReading.Source) -> LocatedReading {
        let sheet = SheetLines(lines: lines)
        var reading = SheetReading(source: source)
        reading.code = sheet.code
        (reading.playerNumber, reading.characterPart) = sheet.characterNumber
        reading.eventCode = sheet.eventCode
        reading.xp = sheet.xp
        reading.funds = sheet.funds
        return LocatedReading(reading: reading, places: sheet.places)
    }
}

/// A value of a sheet that the user confirms (R1.11).
public enum SheetField: String, Hashable, Sendable, CaseIterable {
    case characterNumber, xp, funds
    /// The scenario number, which the user confirms only for a sheet added ahead of its report (R1.14).
    case code
}

/// What was read from a sheet, and where on its page each confirmed value was found.
public struct LocatedReading: Hashable, Sendable {
    public var reading: SheetReading
    /// In fractions of the page, `y` from the top; only the values that were read.
    public var places: [SheetField: CGRect]

    public init(reading: SheetReading = SheetReading(), places: [SheetField: CGRect] = [:]) {
        self.reading = reading
        self.places = places
    }
}

/// A sheet's lines, sorted into its labels and what was written on it.
private struct SheetLines {
    /// What a box holds.
    enum Content {
        case nothing
        case line(RecognizedLine)
        /// More than one line, or a box whose edges aren't known.
        case unclear
    }

    let lines: [RecognizedLine]
    let format: SheetFormat
    private let labels: [SheetLabel: [RecognizedLine]]
    private let written: [RecognizedLine]

    init(lines: [RecognizedLine]) {
        self.lines = lines
        format = SheetFormat(lines: lines)
        labels = Dictionary(grouping: lines.filter { SheetLabel.of($0) != nil }) { SheetLabel.of($0) ?? .eventCode }
        written = lines.filter { !SheetPrinting.isPrinting($0) }
    }

    // MARK: - The top and bottom strips, where every label is under its value

    /// The first code among the lines at the top of the sheet, where its title is; a code further down is another
    /// adventure's, named in the text.
    var code: String? {
        lines.filter { $0.box.midY < Reach.titleArea }
            .sorted { ($0.box.minY, $0.box.minX) < ($1.box.minY, $1.box.minX) }
            .lazy.compactMap { AdventureClassifier.code(inText: $0.text) }.first
    }

    /// The Organized Play number and the character's own part, from the two boxes side by side above their labels.
    /// Recognition may give both as one line ("2409341• 2702"), and most Pathfinder sheets print the character
    /// part's leading "2" themselves, beside the three digits the player writes.
    var characterNumber: (player: String?, part: String?) {
        guard let player = single(.organizedPlayNumber) else { return (nil, nil) }
        let boundary = single(.characterNumber).map { (player.box.maxX + $0.box.minX) / 2 }
        var playerRuns: [String] = []
        var partRuns: [String] = []
        for line in characterNumberLines(above: player) {
            let runs = SheetNumber.digitRuns(in: line.text)
            if let boundary, line.box.midX >= boundary {
                partRuns += runs
            } else {
                playerRuns += runs.prefix(1)
                partRuns += runs.dropFirst()
            }
        }
        return (Self.playerNumber(from: playerRuns), Self.characterPart(from: partRuns))
    }

    /// What is in the two boxes above the character number's labels, left to right.
    private func characterNumberLines(above player: RecognizedLine) -> [RecognizedLine] {
        let rightEdge = (single(.characterNumber) ?? player).box.maxX + Reach.sideways
        return lines.sorted { $0.box.minX < $1.box.minX }.filter { line in
            SheetLabel.of(line) == nil && isJustAbove(line, player)
                && (player.box.minX - Reach.sideways...rightEdge).contains(line.box.midX)
        }
    }

    private static func playerNumber(from runs: [String]) -> String? {
        runs.count == 1 && runs[0].count >= 3 ? runs[0] : nil
    }

    /// "2702" written whole, or the printed "2" and the "702" written beside it.
    private static func characterPart(from runs: [String]) -> String? {
        switch runs.count {
        case 1 where runs[0].count == 4: runs[0]
        case 2 where runs[0] == "2" && runs[1].count == 3: "2" + runs[1]
        default: nil
        }
    }

    var eventCode: String? {
        guard let label = single(.eventCode) else { return nil }
        let above = written.filter { line in
            isJustAbove(line, label) && line.box.midX >= label.box.minX - Reach.besideEventCode
                && line.box.midX <= label.box.maxX + Reach.besideEventCode
        }
        return above.count == 1 ? SheetNumber.eventCode(above[0].text) : nil
    }

    // MARK: - The reward column, where the label's side depends on the format

    var xp: Double? {
        guard case .line(let line) = content(ofBoxFor: .xpGained) else { return nil }
        return SheetNumber.xp(line.text)
    }

    /// The gold box, with the Earn Income box added where the sheet has one (R5.2). An Earn Income box that holds
    /// something unreadable leaves the whole amount unread: the sum would be wrong.
    var funds: Int? {
        guard case .line(let line) = content(ofBoxFor: .fundsGained),
              let gained = SheetNumber.funds(line.text, in: format.currency) else { return nil }
        guard labels[.earnIncome] != nil else { return gained }
        switch content(ofBoxFor: .earnIncome) {
        case .nothing: return gained
        case .line(let income): return SheetNumber.funds(income.text, in: format.currency).map { gained + $0 }
        case .unclear: return nil
        }
    }

    private func content(ofBoxFor label: SheetLabel) -> Content {
        guard let side = format.labelSide, let own = single(label),
              let box = box(of: own, labelSide: side) else { return .unclear }
        let inside = written.filter { line in
            box.contains(line.box.midY) && abs(line.box.midX - own.box.midX) <= Reach.columnHalfWidth
        }
        switch inside.count {
        case 0: return .nothing
        case 1: return .line(inside[0])
        default: return .unclear
        }
    }

    /// From top to bottom, where the box of a reward label is: between the label and the next label on the box's
    /// side. A label under its box always has another above it, so one that has none was missed in reading and
    /// the box's top isn't known. A label over its box may be the column's last, and its box is then a tall one.
    private func box(of own: RecognizedLine, labelSide: SheetFormat.LabelSide) -> ClosedRange<CGFloat>? {
        let column = labels.filter { $0.key.isInRewardColumn }.flatMap(\.value)
            .filter { $0 != own && abs($0.box.midX - own.box.midX) <= Reach.columnHalfWidth }
        switch labelSide {
        case .under:
            guard let above = column.map(\.box.maxY).filter({ $0 <= own.box.midY }).max(),
                  above < own.box.minY else { return nil }
            return above...own.box.minY
        case .over:
            let below = column.map(\.box.minY).filter { $0 >= own.box.midY }.min()
            let bottom = below ?? own.box.maxY + Reach.tallestBox
            return bottom > own.box.maxY ? own.box.maxY...bottom : nil
        }
    }

    // MARK: - Where the values are

    /// Where each value that was read is on the page.
    var places: [SheetField: CGRect] {
        var places: [SheetField: CGRect] = [:]
        let number = characterNumber
        if number.player != nil || number.part != nil, let player = single(.organizedPlayNumber) {
            places[.characterNumber] = Self.union(characterNumberLines(above: player))
        }
        if xp != nil, case .line(let line) = content(ofBoxFor: .xpGained) { places[.xp] = line.box }
        if funds != nil { places[.funds] = Self.union(fundsLines) }
        return places.filter { !$0.value.isNull }
    }

    /// The gold box's line and, where the sheet has the box, the Earn Income one.
    private var fundsLines: [RecognizedLine] {
        [SheetLabel.fundsGained, .earnIncome].compactMap { label in
            guard labels[label] != nil, case .line(let line) = content(ofBoxFor: label) else { return nil }
            return line
        }
    }

    private static func union(_ lines: [RecognizedLine]) -> CGRect {
        lines.reduce(CGRect.null) { $0.union($1.box) }
    }

    // MARK: - Helpers

    /// The label's line when the sheet has it exactly once.
    private func single(_ label: SheetLabel) -> RecognizedLine? {
        guard let found = labels[label], found.count == 1 else { return nil }
        return found[0]
    }

    /// Whether a line is in the strip of boxes right above a label.
    private func isJustAbove(_ line: RecognizedLine, _ label: RecognizedLine) -> Bool {
        line.box.midY < label.box.minY && line.box.midY >= label.box.minY - Reach.stripHeight
    }
}

/// How far from a label its value may be, in fractions of the page; from the census of every sheet's layout
/// (`chronicle-formats.json`).
private enum Reach {
    /// The sheet's title is in its top fifth.
    static let titleArea: CGFloat = 0.2
    /// How far above a label of the top or bottom strip its value is written.
    static let stripHeight: CGFloat = 0.045
    /// How far past the ends of the character number's labels their boxes go.
    static let sideways: CGFloat = 0.06
    /// The same for the event code, which has the event's name and the date close on either side.
    static let besideEventCode: CGFloat = 0.04
    /// How far a reward value's middle may be from its label's: past that is the column's edge, where its
    /// vertical names are.
    static let columnHalfWidth: CGFloat = 0.075
    /// The height of the tallest reward box, season 2's gold box.
    static let tallestBox: CGFloat = 0.12
}
