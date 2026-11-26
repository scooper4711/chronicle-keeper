import CoreGraphics
import Foundation
import Testing
@testable import ChronicleKeeperKit

/// What the reader does with a sheet it can't be sure of: nothing (R1.10).
struct SheetInterpreterTests {
    private typealias Lines = SheetLineFactory

    /// A Starfinder sheet as text recognition gave it from a scan: the label under each box, the "+" read with
    /// the credits, both halves of the character's number as one line, and the sheet's own reward table.
    private static let scannedSheet: [RecognizedLine] = [
        Lines.line("Scenario #1-04", left: 0.43, top: 0.09, width: 0.26),
        Lines.line("Valeria", left: 0.12, top: 0.17, width: 0.09),
        Lines.line("Character Name", left: 0.26, top: 0.19, width: 0.09),
        Lines.line("123451• 2702", left: 0.54, top: 0.17, width: 0.19),
        Lines.line("Organized Play #", left: 0.55, top: 0.19, width: 0.09),
        Lines.line("Character #", left: 0.66, top: 0.19, width: 0.07),
        Lines.line("CR", left: 0.77, top: 0.19, width: 0.01),
        Lines.line("LEVEL", left: 0.78, top: 0.18, width: 0.03),
        Lines.line("2", left: 0.80, top: 0.21, width: 0.01),
        Lines.line("220 credits", left: 0.84, top: 0.20, width: 0.07),
        Lines.line("Starting XP", left: 0.82, top: 0.29, width: 0.06),
        Lines.line("+", left: 0.78, top: 0.35, width: 0.01),
        Lines.line("4", left: 0.84, top: 0.34, width: 0.02),
        Lines.line("XP Gained (GM ONLY)", left: 0.80, top: 0.38, width: 0.12),
        Lines.line("Final XP Total", left: 0.82, top: 0.46, width: 0.08),
        Lines.line("Starting Credits", left: 0.81, top: 0.54, width: 0.09),
        Lines.line("+ 220", left: 0.78, top: 0.59, width: 0.09),
        Lines.line("Credits Gained (GM ONLY)", left: 0.78, top: 0.62, width: 0.14),
        Lines.line("Credits Spent", left: 0.82, top: 0.70, width: 0.07),
        Lines.line("Total", left: 0.84, top: 0.78, width: 0.03),
        Lines.line("Lantern Fair 2026", left: 0.06, top: 0.86, width: 0.14),
        Lines.line("EVENT", left: 0.25, top: 0.87, width: 0.03),
        Lines.line("1,234,127", left: 0.47, top: 0.85, width: 0.06),
        Lines.line("EVENT CODE", left: 0.51, top: 0.87, width: 0.06),
        Lines.line("21-Nov-2026", left: 0.61, top: 0.85, width: 0.07),
        Lines.line("DATE", left: 0.67, top: 0.87, width: 0.03)
    ]

    private func reading(_ lines: [RecognizedLine]) -> SheetReading {
        SheetInterpreter.reading(of: lines, source: .recognized)
    }

    @Test func aScannedSheetIsRead() {
        let reading = reading(Self.scannedSheet)
        #expect(reading.code == "1-04")
        #expect(reading.playerNumber == "123451")
        #expect(reading.characterPart == "2702")
        #expect(reading.xp == 4)
        #expect(reading.funds == 2_200)
        #expect(reading.eventCode == "1234127")
        #expect(reading.source == .recognized)
        #expect(!reading.isEmpty)
    }

    @Test func twoNumbersInABoxAreNotChosenBetween() {
        let reading = reading(Self.scannedSheet + [Lines.line("8", left: 0.86, top: 0.60, width: 0.02)])
        #expect(reading.funds == nil)
        #expect(reading.xp == 4)
    }

    @Test func aNumberWithOtherWritingIsNotRead() {
        let lines = Self.scannedSheet.map {
            $0.text == "+ 220" ? Lines.line("220 + 8 income", left: 0.78, top: 0.59) : $0
        }
        #expect(reading(lines).funds == nil)
    }

    @Test func aLabelFoundTwiceLeavesItsBoxUnread() {
        let reading = reading(Self.scannedSheet + [Lines.line("XP Gained", left: 0.82, top: 0.42, width: 0.06)])
        #expect(reading.xp == nil)
    }

    /// Without "Final XP" or "Total XP" a sheet that has "Starting XP" doesn't say which side its boxes are on.
    @Test func aSheetWhoseFormatIsUnclearGivesNoRewards() {
        let withoutTotal = Self.scannedSheet.filter { $0.text != "Final XP Total" }
        #expect(SheetFormat(lines: withoutTotal).labelSide == nil)
        #expect(reading(withoutTotal).xp == nil)
        #expect(reading(withoutTotal).funds == nil)
        let withBoth = Self.scannedSheet + [Lines.line("Total XP", left: 0.82, top: 0.50)]
        #expect(SheetFormat(lines: withBoth).labelSide == nil)
        #expect(reading(withBoth).xp == nil)
    }

    /// A label under its box has another label above it: when that one wasn't read, the box's top isn't known.
    @Test func aBoxWithoutItsUpperEdgeIsNotRead() {
        let lines = Self.scannedSheet.filter { $0.text != "Starting XP" }
        #expect(reading(lines).xp == nil)
    }

    @Test func aCodeFurtherDownTheSheetIsNotTheSheets() {
        let lines = Self.scannedSheet.filter { $0.text != "Scenario #1-04" }
            + [Lines.line("as you did in Scenario #1-02", left: 0.1, top: 0.4, width: 0.3)]
        #expect(reading(lines).code == nil)
    }

    @Test func theCharacterNumberIsReadFromEitherBoxAlone() {
        let onlyPlayer = Self.scannedSheet.map {
            $0.text == "123451• 2702" ? Lines.line("123451", left: 0.56, top: 0.17, width: 0.06) : $0
        }
        #expect(reading(onlyPlayer).playerNumber == "123451")
        #expect(reading(onlyPlayer).characterPart == nil)
        let onlyPart = Self.scannedSheet.map {
            $0.text == "123451• 2702" ? Lines.line("2702", left: 0.67, top: 0.17, width: 0.04) : $0
        }
        #expect(reading(onlyPart).playerNumber == nil)
        #expect(reading(onlyPart).characterPart == "2702")
    }

    @Test func aCharacterPartThatIsNotFourDigitsIsNotRead() {
        let lines = Self.scannedSheet.map {
            $0.text == "123451• 2702" ? Lines.line("123451 - 27", left: 0.54, top: 0.17, width: 0.19) : $0
        }
        #expect(reading(lines).playerNumber == "123451")
        #expect(reading(lines).characterPart == nil)
    }

    @Test func anEventCodeThatIsNotANumberIsNotRead() {
        let lines = Self.scannedSheet.map { $0.text == "1,234,127" ? Lines.line("online", left: 0.47, top: 0.85) : $0 }
        #expect(reading(lines).eventCode == nil)
    }

    @Test func noLinesGiveAnEmptyReading() {
        #expect(reading([]).isEmpty)
    }

    // MARK: - Earn Income, which only the first format has a box for

    /// Season 1's column: every label under its box.
    private static func seasonOneColumn(gold: String?, income: String?) -> [RecognizedLine] {
        var lines = [
            Lines.line("Starting XP", left: 0.826, top: 0.383), Lines.line("XP Gained", left: 0.829, top: 0.429),
            Lines.line("Final XP", left: 0.835, top: 0.476), Lines.line("Starting GP", left: 0.826, top: 0.522),
            Lines.line("GP Gained", left: 0.829, top: 0.569), Lines.line("Earn Income", left: 0.823, top: 0.616),
            Lines.line("Items Sold", left: 0.829, top: 0.662)
        ]
        if let gold { lines.append(Lines.line(gold, left: 0.84, top: 0.545, width: 0.04)) }
        if let income { lines.append(Lines.line(income, left: 0.84, top: 0.592, width: 0.04)) }
        return lines
    }

    @Test func earnIncomeIsAddedToTheGold() {
        #expect(reading(Self.seasonOneColumn(gold: "11.2", income: "0.8")).funds == 1_200)
        #expect(reading(Self.seasonOneColumn(gold: "11.2", income: nil)).funds == 1_120)
    }

    @Test func earnIncomeThatCannotBeReadLeavesTheGoldUnread() {
        #expect(reading(Self.seasonOneColumn(gold: "11.2", income: "8 sp")).funds == nil)
        #expect(reading(Self.seasonOneColumn(gold: nil, income: "0.8")).funds == nil)
    }
}

struct SheetNumberTests {
    @Test(arguments: [
        ("4", 4.0), ("+ 4", 4), ("4.0", 4), ("2", 2), ("0,5", 0.5), ("12", 12), ("2 XP", 2), ("1.50", 1.5)
    ])
    func xpAsWritten(text: String, xp: Double) {
        #expect(SheetNumber.xp(text) == xp)
    }

    @Test(arguments: ["", "four", "4/4", "4 2", "123", "-4"])
    func whatIsNotXP(text: String) {
        #expect(SheetNumber.xp(text) == nil)
    }

    @Test(arguments: [
        ("220", 22_000), ("+ 11.2", 1_120), ("13,2", 1_320), ("14 gp", 1_400), ("176.00", 17_600),
        ("1,234", 123_400), ("1.234", 123_400), ("12 345", 1_234_500), ("0.05", 5), ("0", 0)
    ])
    func goldAsWritten(text: String, copper: Int) {
        #expect(SheetNumber.funds(text, in: .gold) == copper)
    }

    @Test(arguments: [("220", 2_200), ("+ 220", 2_200), ("220 credits", 2_200), ("1,400 cr", 14_000), ("38.5", 385)])
    func creditsAsWritten(text: String, copper: Int) {
        #expect(SheetNumber.funds(text, in: .credits) == copper)
    }

    @Test(arguments: ["", "14 gp 4 sp", "eleven", "11.234.5", "11.2.3", "1,23,4", "-5"])
    func whatIsNotAnAmount(text: String) {
        #expect(SheetNumber.funds(text, in: .gold) == nil)
    }

    /// A credit is worth a silver piece, so a hundredth of one is less than a copper.
    @Test func aFractionOfACopperIsNotAnAmount() {
        #expect(SheetNumber.funds("38.55", in: .credits) == nil)
    }

    @Test func eventCodesLoseTheirSeparators() {
        #expect(SheetNumber.eventCode("8,538,127") == "8538127")
        #expect(SheetNumber.eventCode("8 538 127") == "8538127")
        #expect(SheetNumber.eventCode("12") == nil)
        #expect(SheetNumber.eventCode("PaizoCon") == nil)
    }

    @Test func digitRunsAreReadLeftToRight() {
        #expect(SheetNumber.digitRuns(in: "2409341• 2702") == ["2409341", "2702"])
        #expect(SheetNumber.digitRuns(in: "123456-2001") == ["123456", "2001"])
        #expect(SheetNumber.digitRuns(in: "none").isEmpty)
    }
}

struct SheetLabelTests {
    private func line(_ text: String, width: CGFloat = 0.06, height: CGFloat = 0.012) -> RecognizedLine {
        RecognizedLine(text: text, box: CGRect(x: 0.8, y: 0.4, width: width, height: height))
    }

    @Test func labelsAreKnownHoweverTheSeasonWordsThem() {
        #expect(SheetLabel.of(line("GP Gained")) == .fundsGained)
        #expect(SheetLabel.of(line("Gold Gained (GM ONLY)")) == .fundsGained)
        #expect(SheetLabel.of(line("Credits  Gained  (GM ONLY)")) == .fundsGained)
        #expect(SheetLabel.of(line("EVENT CODE")) == .eventCode)
        #expect(SheetLabel.of(line("Final XP Total")) == .finalXP)
        #expect(SheetLabel.of(line("Total")) == .totalFunds)
    }

    @Test func aLineThatOnlyMentionsALabelIsNotOne() {
        #expect(SheetLabel.of(line("checks to Earn Income attempted using the item")) == nil)
        #expect(SheetLabel.of(line("XP Gained: 4")) == nil)
    }

    @Test func theSheetsOwnPrintingIsNotWriting() {
        #expect(SheetPrinting.isPrinting(line("FOR GM ONLY")))
        #expect(SheetPrinting.isPrinting(line("+")))
        #expect(SheetPrinting.isPrinting(line("\u{00AD}-")))
        #expect(SheetPrinting.isPrinting(line("EXPERIENCE", width: 0.016, height: 0.057)))
        #expect(!SheetPrinting.isPrinting(line("220")))
        #expect(!SheetPrinting.isPrinting(line("1", width: 0.006, height: 0.013)))
    }

    @Test func theCurrencyComesFromTheGoldBoxsWording() {
        #expect(SheetFormat(lines: [line("Credits Gained (GM ONLY)")]).currency == .credits)
        #expect(SheetFormat(lines: [line("GP Gained")]).currency == .gold)
        #expect(SheetFormat(lines: []).currency == .gold)
    }
}

struct SheetReadingTests {
    @Test func aReadingSurvivesSavingAndKeepsWhatItDoesNotKnow() throws {
        let saved = #"{"code":"6-04","xp":4,"funds":1120,"source":"pdfText","clearedWarnings":["xp:4"],"later":[1]}"#
        let reading = try JSONDecoder().decode(SheetReading.self, from: Data(saved.utf8))
        #expect(reading.code == "6-04")
        #expect(reading.xp == 4)
        #expect(reading.funds == 1_120)
        #expect(reading.clearedWarnings == ["xp:4"])
        let again = try JSONDecoder().decode(SheetReading.self, from: JSONEncoder().encode(reading))
        #expect(again == reading)
        #expect(again.unknownFields.values["later"] == .array([.number(1)]))
    }

    /// A newer version may read sheets another way; what it read is then treated as needing a check.
    @Test func anUnknownSourceCountsAsRecognized() throws {
        let reading = try JSONDecoder().decode(SheetReading.self, from: Data(#"{"source":"hologram"}"#.utf8))
        #expect(reading.source == .recognized)
        #expect(reading.isEmpty)
    }
}
