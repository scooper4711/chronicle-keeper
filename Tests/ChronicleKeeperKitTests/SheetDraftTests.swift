import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import ChronicleKeeperKit

/// The confirmation's fields: what was read as text, and the reading the user's edits make of it (R1.11).
struct SheetDraftTests {
    private func reading(_ change: (inout SheetReading) -> Void = { _ in }) -> SheetReading {
        var reading = SheetReading(source: .recognized)
        reading.code = "6-04"
        reading.eventCode = "7654321"
        change(&reading)
        return reading
    }

    private func draft(number: String = "", xp: String = "", funds: String = "") -> SheetDraft {
        var draft = SheetDraft(reading: SheetReading(), currency: .gold)
        draft.characterNumber = number
        draft.xp = xp
        draft.funds = funds
        return draft
    }

    @Test func theFieldsShowWhatWasRead() {
        let draft = SheetDraft(
            reading: reading { $0.playerNumber = "123456"; $0.characterPart = "2001"; $0.xp = 4; $0.funds = 22_000 },
            currency: .credits)
        #expect(draft.characterNumber == "123456-2001")
        #expect(draft.xp == "4")
        #expect(draft.funds == Money.format(22_000, in: .credits))
    }

    @Test func whatWasNotReadIsAnEmptyField() {
        let draft = SheetDraft(reading: reading { $0.characterPart = "2001" }, currency: .gold)
        #expect(draft.characterNumber == "2001")
        #expect(draft.xp.isEmpty)
        #expect(draft.funds.isEmpty)
    }

    @Test func anUneditedDraftGivesTheReadingBack() {
        let read = reading { $0.playerNumber = "123456"; $0.characterPart = "2001"; $0.xp = 0.5; $0.funds = 1_120 }
        let draft = SheetDraft(reading: read, currency: .gold)
        #expect(draft.unreadableFields(in: .gold).isEmpty)
        #expect(draft.reading(correcting: read, currency: .gold) == read)
    }

    @Test func editsReplaceWhatWasReadAndKeepTheRest() {
        let read = reading { $0.playerNumber = "123451"; $0.characterPart = "2001"; $0.xp = 4 }
        let corrected = draft(number: "123456-2001", xp: "2", funds: "11.2 gp")
            .reading(correcting: read, currency: .gold)
        #expect(corrected.playerNumber == "123456")
        #expect(corrected.xp == 2)
        #expect(corrected.funds == Money.parse("11.2 gp", in: .gold))
        #expect(corrected.code == "6-04")
        #expect(corrected.eventCode == "7654321")
        #expect(corrected.source == .recognized)
    }

    @Test func anEmptiedFieldIsAValueLeftUnread() {
        let read = reading { $0.characterPart = "2001"; $0.xp = 4; $0.funds = 1_120 }
        let emptied = draft().reading(correcting: read, currency: .gold)
        #expect(emptied.characterPart == nil)
        #expect(emptied.xp == nil)
        #expect(emptied.funds == nil)
        #expect(draft().unreadableFields(in: .gold).isEmpty)
    }

    /// What the user typed, then the Organized Play number and the character's part it gives ("" for none).
    @Test(arguments: [
        ["2001", "", "2001"], ["-701", "", "701"], ["123456", "123456", ""], ["123456-", "123456", ""],
        ["123456 2001", "123456", "2001"], ["123456–2001", "123456", "2001"]
    ])
    func aCharacterNumberIsReadInItsParts(typed: [String]) {
        let corrected = draft(number: typed[0]).reading(correcting: SheetReading(), currency: .gold)
        #expect(corrected.playerNumber ?? "" == typed[1])
        #expect(corrected.characterPart ?? "" == typed[2])
    }

    @Test func textThatIsNotAValueIsNamed() {
        #expect(draft(number: "Valeria").unreadableFields(in: .gold) == [.characterNumber])
        #expect(draft(number: "1-2-3").unreadableFields(in: .gold) == [.characterNumber])
        #expect(draft(number: "-").unreadableFields(in: .gold) == [.characterNumber])
        #expect(draft(xp: "four").unreadableFields(in: .gold) == [.xp])
        #expect(draft(funds: "lots").unreadableFields(in: .gold) == [.funds])
        #expect(draft(funds: "lots").reading(correcting: SheetReading(), currency: .gold).funds == nil)
    }

    @Test func aReadingIsSummedUpOnOneLine() {
        let read = reading { $0.playerNumber = "123456"; $0.characterPart = "2001"; $0.xp = 4; $0.funds = 22_000 }
        #expect(read.summary(in: .credits) == "4 XP · \(Money.format(22_000, in: .credits)) · character 123456-2001")
        #expect(reading { $0.characterPart = "2001" }.summary(in: .gold) == "character 2001")
        #expect(SheetReading().summary(in: .gold) == "nothing could be read for certain")
    }

    /// Turning a sideways page reads it again: the fields take the new values, except one the user typed.
    @Test func aSheetReadAgainRefillsOnlyTheFieldsTheUserLeftAlone() {
        let earlier = draft()
        var shown = earlier
        shown.xp = "2"
        shown.refill(from: draft(number: "123456-2001", xp: "4", funds: "11.2 gp"), replacing: earlier)
        #expect(shown.characterNumber == "123456-2001")
        #expect(shown.xp == "2")
        #expect(shown.funds == "11.2 gp")
    }
}

/// Where the values were read on the page, for marking them in the confirmation (R1.11).
struct SheetPlaceTests {
    @Test func eachValueReadHasItsPlace() throws {
        let lines = PDFTextLines.lines(of: try SheetPDFFactory.pdf(SheetPDFFactory.filledSheet()))
        let located = SheetInterpreter.locatedReading(of: lines, source: .pdfText)
        let xp = try #require(located.places[.xp])
        let funds = try #require(located.places[.funds])
        let number = try #require(located.places[.characterNumber])
        #expect(abs(xp.minY - 0.355) < 0.01)
        #expect(abs(funds.minY - 0.457) < 0.01)
        // The Organized Play number and the character's part, as one place.
        #expect(number.minX < 0.71)
        #expect(number.maxX > 0.87)
    }

    @Test func aValueThatWasNotReadHasNoPlace() throws {
        let lines = PDFTextLines.lines(of: try SheetPDFFactory.pdf(SheetPDFFactory.filledSheet(xp: "", gold: "")))
        let located = SheetInterpreter.locatedReading(of: lines, source: .pdfText)
        #expect(Set(located.places.keys) == [.characterNumber])
        #expect(SheetInterpreter.locatedReading(of: [], source: .pdfText) == LocatedReading())
    }

    @Test func turningAPDFTurnsItsPagesAndWrapsAround() throws {
        let pdf = try SheetPDFFactory.pdf([PlacedText("XP Gained", 0.1, 0.2)])
        let right = try #require(SheetPage.turned(pdf, quarterTurns: 1))
        #expect(PDFDocument(data: right)?.page(at: 0)?.rotation == 90)
        let left = try #require(SheetPage.turned(pdf, quarterTurns: -1))
        #expect(PDFDocument(data: left)?.page(at: 0)?.rotation == 270)
        let around = try #require(SheetPage.turned(right, quarterTurns: 3))
        #expect(PDFDocument(data: around)?.page(at: 0)?.rotation == 0)
        #expect(SheetPage.turned(Data("not a PDF".utf8), quarterTurns: 1) == nil)
    }

    /// A place on the page as shown lands on the same text in the page's own points, however the page is turned.
    @Test(arguments: [0, 90, 180, 270])
    func aPlaceIsFoundAgainInThePagesOwnPoints(rotation: Int) throws {
        let pdf = try SheetPDFFactory.pdf([PlacedText("XP Gained", 0.1, 0.2)], rotation: rotation)
        let page = try #require(PDFDocument(data: pdf)?.page(at: 0))
        let line = try #require(PDFTextLines.lines(of: pdf).first)
        let box = SheetPage.pageBox(of: line.box, on: page)
        let expected = CGPoint(x: 0.1 * SheetPDFFactory.page.width, y: 0.8 * SheetPDFFactory.page.height - 9)
        #expect(abs(box.minX - expected.x) < 3)
        #expect(abs(box.minY - expected.y) < 5)
    }
}
