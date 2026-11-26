import Foundation

/// What a chronicle sheet prints beside a box: the boxes the reader takes a value from, and the ones next to them,
/// whose labels say where a box ends.
enum SheetLabel: CaseIterable, Sendable {
    case organizedPlayNumber, characterNumber, eventCode
    case startingXP, xpGained, finalXP, totalXP
    case startingFunds, fundsGained, earnIncome, itemsSold, fundsSpent, totalFunds
    case startingFame, fameEarned, totalFame

    /// The label a line is, when the line is nothing but that label.
    static func of(_ line: RecognizedLine) -> SheetLabel? {
        var text = line.plainText
        if text.hasSuffix(gameMasterOnly) { text = String(text.dropLast(gameMasterOnly.count)) }
        return allCases.first { $0.wordings.contains(text) }
    }

    /// Season 8 and Starfinder sheets add this to the boxes the GM fills in.
    private static let gameMasterOnly = " (gm only)"

    /// How the sheets of different seasons word it, in lower case.
    var wordings: [String] {
        switch self {
        case .organizedPlayNumber: ["organized play #"]
        case .characterNumber: ["character #"]
        case .eventCode: ["event code"]
        case .startingXP: ["starting xp"]
        case .xpGained: ["xp gained"]
        case .finalXP: ["final xp", "final xp total"]
        case .totalXP: ["total xp"]
        case .startingFunds: ["starting gp", "starting gold", "starting credits"]
        case .fundsGained: ["gp gained", "gold gained", "credits gained"]
        case .earnIncome: ["earn income"]
        case .itemsSold: ["items sold"]
        case .fundsSpent: ["gp spent", "gold spent", "credits spent"]
        case .totalFunds: ["total gp", "total"]
        case .startingFame: ["starting fame"]
        case .fameEarned: ["fame earned"]
        case .totalFame: ["total fame"]
        }
    }

    /// Whether the label is one of the column of reward boxes down the sheet's right side.
    var isInRewardColumn: Bool {
        switch self {
        case .organizedPlayNumber, .characterNumber, .eventCode: false
        default: true
        }
    }
}

/// The sheet's own printing that isn't a box's label: the names along the reward column, its heading, the signs
/// between its boxes, the dash before the character number and the banner over the GM's strip, which is right
/// above the event code. None of it is something a GM wrote.
enum SheetPrinting {
    static func isPrinting(_ line: RecognizedLine) -> Bool {
        line.isVertical || SheetLabel.of(line) != nil || words.contains(line.plainText)
    }

    private static let words: Set<String> = [
        "experience", "gold", "credits", "rewards", "level", "reputation", "faction", "for gm only",
        "+", "-", "–", "—", "="
    ]
}

/// Where a sheet's reward boxes are, which changed over the years (design.md, "Reading a chronicle sheet").
struct SheetFormat: Hashable, Sendable {
    /// Which side of its box a reward label is printed on.
    enum LabelSide: Sendable {
        /// Under the box: the value is above its label (season 1, season 8, Starfinder).
        case under
        /// Over the box: the value is below its label (seasons 2 to 7).
        case over
    }

    /// Nil when the labels read don't settle it, and then no reward is read.
    let labelSide: LabelSide?
    /// What the sheet pays in, from how it words the gold box.
    let currency: Currency

    /// "Final XP" is only on sheets with the label under the box, "Total XP" only on those with it over. The
    /// sheets with neither total (most of season 2) have no "Starting XP" either, and print the label over.
    init(lines: [RecognizedLine]) {
        let labels = Set(lines.compactMap(SheetLabel.of))
        switch (labels.contains(.finalXP), labels.contains(.totalXP)) {
        case (true, false): labelSide = .under
        case (false, true): labelSide = .over
        case (false, false): labelSide = labels.contains(.startingXP) ? nil : .over
        case (true, true): labelSide = nil
        }
        let paysCredits = lines.contains { SheetLabel.of($0) == .fundsGained && $0.plainText.hasPrefix("credits") }
        currency = paysCredits ? .credits : .gold
    }
}
