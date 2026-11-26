import CoreGraphics
import Testing
@testable import ChronicleKeeperKit

/// The sheet reader against every chronicle layout there is (R1.10): Paizo moved the reward boxes' labels over the
/// years, and a reader that assumed one layout would read the wrong box on half the sheets.
struct SheetCensusTests {
    @Test func theCensusHoldsEverySheet() {
        #expect(SheetCensus.all.count == 241)
        #expect(SheetCensus.withValues.count == 237)
    }

    /// The side the sheet's own labels give is the side its layout writes the XP on.
    @Test(arguments: SheetCensus.withValues)
    func theLabelSideIsReadFromTheSheetsOwnLabels(sheet: SheetCensus.Sheet) throws {
        let label = try #require(sheet.label(.xpGained))
        let value = try #require(sheet.box(of: "xp"))
        let expected: SheetFormat.LabelSide = value.midY < label.box.midY ? .under : .over
        #expect(SheetFormat(lines: sheet.lines).labelSide == expected)
    }

    @Test(arguments: SheetCensus.all)
    func aBlankSheetGivesNoValues(sheet: SheetCensus.Sheet) {
        let reading = SheetInterpreter.reading(of: sheet.lines, source: .pdfText)
        #expect(reading.xp == nil)
        #expect(reading.funds == nil)
        #expect(reading.playerNumber == nil)
        #expect(reading.characterPart == nil)
        #expect(reading.eventCode == nil)
    }

    /// Every box in the reward column filled in, so that reading the box on the wrong side of a label, or the
    /// next box along, gives a wrong number rather than none.
    @Test(arguments: SheetCensus.withValues)
    func valuesAreReadFromTheirOwnBoxes(sheet: SheetCensus.Sheet) throws {
        let filled = try FilledSheet(sheet)
        let reading = SheetInterpreter.reading(of: filled.lines, source: .pdfText)
        #expect(reading.xp == 4)
        #expect(reading.funds == filled.expectedFunds)
        #expect(reading.playerNumber == "123456")
        #expect(reading.characterPart == "2702")
        // Nine season 4 layouts put the event code in the event name's box; the census leaves that box out.
        #expect(reading.eventCode == (filled.hasEventCode ? "1234567" : nil))
    }

    @Test(arguments: SheetCensus.all)
    func theCodeIsReadFromTheTitle(sheet: SheetCensus.Sheet) {
        let reading = SheetInterpreter.reading(of: sheet.lines, source: .pdfText)
        let printsNoNumber = Self.sheetsWithoutANumber.contains { sheet.sheet.hasSuffix($0) }
        #expect(reading.code == (printsNoNumber ? nil : sheet.code))
    }

    /// Sheets whose title has no number to read: "Pathfinder Society Intro: Year of Immortal Influence".
    private static let sheetsWithoutANumber = ["6-01-YearofImmortalInfluenceChronicle"]
}

/// A census sheet with every value written in the box its layout gives, and a wrong number in every other box of
/// the reward column.
private struct FilledSheet {
    let lines: [RecognizedLine]
    let expectedFunds: Int
    let hasEventCode: Bool

    init(_ sheet: SheetCensus.Sheet) throws {
        let format = SheetFormat(lines: sheet.lines)
        let boxes = try (
            xp: #require(sheet.box(of: "xp")), funds: #require(sheet.box(of: "funds")),
            player: #require(sheet.box(of: "player")), part: #require(sheet.box(of: "character")))
        let eventCode = sheet.box(of: "eventCode")
        hasEventCode = eventCode != nil
        let printsTheTwo = sheet.lines.contains { $0.text == "2" && abs($0.box.midY - boxes.part.midY) < 0.02 }
        var lines = sheet.lines
        lines.append(SheetLineFactory.written("4", in: boxes.xp))
        lines.append(SheetLineFactory.written(format.currency == .credits ? "220" : "13.2", in: boxes.funds))
        lines.append(SheetLineFactory.written("123456", in: boxes.player))
        lines.append(SheetLineFactory.written(printsTheTwo ? "702" : "2702", in: boxes.part))
        if let eventCode { lines.append(SheetLineFactory.written("1,234,567", in: eventCode)) }
        lines += Self.decoys(on: sheet, avoiding: [boxes.xp, boxes.funds], labelSide: format.labelSide)
        self.lines = lines
        expectedFunds = format.currency == .credits ? 2_200 : 1_320
    }

    /// A "9" between each two reward labels that have none of the real values between them. The Earn Income box
    /// is left empty, as what is in it is added to the gold.
    private static func decoys(
        on sheet: SheetCensus.Sheet, avoiding real: [CGRect], labelSide: SheetFormat.LabelSide?
    ) -> [RecognizedLine] {
        let labels = sheet.lines
            .filter { SheetLabel.of($0)?.isInRewardColumn == true }.sorted { $0.box.minY < $1.box.minY }
        return zip(labels, labels.dropFirst()).compactMap { upper, lower in
            let gap = upper.box.maxY...max(upper.box.maxY, lower.box.minY)
            let isEarnIncomeBox = SheetLabel.of(labelSide == .under ? lower : upper) == .earnIncome
            guard !isEarnIncomeBox, !real.contains(where: { gap.contains($0.midY) }),
                  gap.upperBound - gap.lowerBound > 0.015 else { return nil }
            let middle = CGRect(x: upper.box.minX, y: gap.lowerBound, width: upper.box.width,
                                height: gap.upperBound - gap.lowerBound)
            return SheetLineFactory.written("9", in: middle)
        }
    }
}
