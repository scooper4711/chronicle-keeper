import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Testing
@testable import ChronicleKeeperKit

/// A text and where its left end and its top are, in fractions of the page.
struct PlacedText {
    let text: String
    let left: CGFloat
    let top: CGFloat

    init(_ text: String, _ left: CGFloat, _ top: CGFloat) {
        self.text = text
        self.left = left
        self.top = top
    }
}

/// Draws chronicle sheets as a program would write them: text at places on a letter-size page.
enum SheetPDFFactory {
    static let page = CGSize(width: 603, height: 783)

    /// A season 3 to 7 sheet (each reward label over its box) with these values written in.
    static func filledSheet(xp: String = "4", gold: String = "11.2") -> [PlacedText] {
        let strips = [
            PlacedText("Scenario #3-03:", 0.55, 0.04), PlacedText("123456", 0.70, 0.125),
            PlacedText("2", 0.845, 0.125), PlacedText("001", 0.87, 0.125),
            PlacedText("Character Name", 0.30, 0.145), PlacedText("Organized Play #", 0.69, 0.145),
            PlacedText("Character #", 0.847, 0.145), PlacedText("7,654,321", 0.53, 0.922),
            PlacedText("EVENT CODE", 0.529, 0.938)
        ]
        let rewards = [
            PlacedText("Rewards", 0.837, 0.294), PlacedText("Starting XP", 0.826, 0.307),
            PlacedText("XP Gained", 0.829, 0.341), PlacedText(xp, 0.857, 0.355),
            PlacedText("Total XP", 0.835, 0.375), PlacedText("Starting GP", 0.826, 0.409),
            PlacedText("GP Gained", 0.829, 0.443), PlacedText(gold, 0.843, 0.457),
            PlacedText("GP Spent", 0.833, 0.477), PlacedText("Total GP", 0.835, 0.511)
        ]
        return strips + rewards
    }

    /// A one-page PDF with each text drawn at its place.
    static func pdf(_ texts: [PlacedText], rotation: Int = 0) throws -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: page)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 9, nil)
        for placed in texts {
            let attributed = NSAttributedString(
                string: placed.text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            context.textPosition = CGPoint(
                x: placed.left * page.width, y: page.height - placed.top * page.height - 9)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        context.endPDFPage()
        context.closePDF()
        guard rotation != 0 else { return data as Data }
        let document = try #require(PDFDocument(data: data as Data))
        try #require(document.page(at: 0)).rotation = rotation
        return try #require(document.dataRepresentation())
    }
}

/// Gives the lines it was made with, and counts how often it was asked.
private final class RecordedRecognizer: TextRecognizer, @unchecked Sendable {
    private let lock = NSLock()
    private let recorded: [RecognizedLine]
    private var count = 0

    init(_ recorded: [RecognizedLine]) { self.recorded = recorded }

    var timesAsked: Int { lock.withLock { count } }

    func lines(in image: CGImage) async throws -> [RecognizedLine] {
        lock.withLock { count += 1 }
        return recorded
    }
}

struct PDFTextLinesTests {
    @Test func aPDFsTextComesAsLinesWhereTheyAre() throws {
        let texts = [PlacedText("XP Gained", 0.83, 0.34), PlacedText("4", 0.86, 0.36)]
        let lines = PDFTextLines.lines(of: try SheetPDFFactory.pdf(texts))
        let label = try #require(lines.first { $0.text == "XP Gained" })
        #expect(abs(label.box.minX - 0.83) < 0.01)
        #expect(abs(label.box.minY - 0.34) < 0.01)
        let value = try #require(lines.first { $0.text == "4" })
        #expect(value.box.minY > label.box.minY)
    }

    /// PDFKit's own lines run across the page; a label must not be joined to what is printed beside it.
    @Test func textsSideBySideAreSeparateLines() throws {
        let texts = [PlacedText("Organized Play #", 0.55, 0.16), PlacedText("Character #", 0.72, 0.16)]
        let pdf = try SheetPDFFactory.pdf(texts)
        #expect(Set(PDFTextLines.lines(of: pdf).map(\.text)) == ["Organized Play #", "Character #"])
    }

    @Test func aTurnedPageGivesItsLinesTheWayUpItIsShown() throws {
        let pdf = try SheetPDFFactory.pdf([PlacedText("XP Gained", 0.1, 0.2)], rotation: 180)
        let line = try #require(PDFTextLines.lines(of: pdf).first)
        #expect(line.box.maxX > 0.85)
        #expect(line.box.maxY > 0.75)
    }

    @Test func whatIsNotAPDFHasNoLines() {
        #expect(PDFTextLines.lines(of: Data("not a PDF".utf8)).isEmpty)
    }
}

struct SheetReaderTests {
    @Test func aSheetWrittenByAProgramIsReadFromItsOwnText() async throws {
        let recognizer = RecordedRecognizer([])
        let pdf = try SheetPDFFactory.pdf(SheetPDFFactory.filledSheet())
        let reading = await SheetReader(recognizer: recognizer).reading(of: pdf)
        #expect(reading.source == .pdfText)
        #expect(reading.code == "3-03")
        #expect(reading.xp == 4)
        #expect(reading.funds == 1_120)
        #expect(reading.playerNumber == "123456")
        #expect(reading.characterPart == "2001")
        #expect(reading.eventCode == "7654321")
        #expect(recognizer.timesAsked == 0)
    }

    /// A sheet filled in by hand on a printed PDF: its text has the labels and no values.
    @Test func aSheetWithoutWrittenValuesIsRecognized() async throws {
        let printed = SheetPDFFactory.filledSheet(xp: "", gold: "")
        let seen = [
            SheetLineFactory.line("Scenario #3-03", left: 0.55, top: 0.04),
            SheetLineFactory.line("XP Gained", left: 0.829, top: 0.341),
            SheetLineFactory.line("2", left: 0.857, top: 0.355, width: 0.01),
            SheetLineFactory.line("Total XP", left: 0.835, top: 0.375)
        ]
        let recognizer = RecordedRecognizer(seen)
        let reading = await SheetReader(recognizer: recognizer).reading(of: try SheetPDFFactory.pdf(printed))
        #expect(reading.source == .recognized)
        #expect(reading.xp == 2)
        #expect(recognizer.timesAsked == 1)
    }

    /// The Beginner Box's sheet and a few others print no number.
    @Test func aSheetWithoutACodeIsStillReadFromItsOwnText() async throws {
        let recognizer = RecordedRecognizer([])
        let sheet = SheetPDFFactory.filledSheet().filter { $0.text != "Scenario #3-03:" }
        let reading = await SheetReader(recognizer: recognizer).reading(of: try SheetPDFFactory.pdf(sheet))
        #expect(reading.source == .pdfText)
        #expect(reading.code == nil)
        #expect(reading.xp == 4)
        #expect(recognizer.timesAsked == 0)
    }

    @Test func whenRecognitionFindsNothingThePDFsTextStands() async throws {
        let printed = try SheetPDFFactory.pdf(SheetPDFFactory.filledSheet(xp: "", gold: ""))
        let reading = await SheetReader(recognizer: RecordedRecognizer([])).reading(of: printed)
        #expect(reading.source == .pdfText)
        #expect(reading.code == "3-03")
        #expect(reading.xp == nil)
    }

    @Test func whatIsNotAPDFReadsAsNothing() async {
        let reading = await SheetReader(recognizer: RecordedRecognizer([])).reading(of: Data("not a PDF".utf8))
        #expect(reading.isEmpty)
    }

    @Test func aPagesPictureIsAsWideAsAsked() throws {
        let image = try #require(SheetPage.image(of: try SheetPDFFactory.pdf([PlacedText("XP Gained", 0.5, 0.5)])))
        #expect(CGFloat(image.width) == SheetPage.recognitionWidth)
        #expect(image.height > image.width)
        #expect(SheetPage.image(of: Data()) == nil)
        let small = try #require(SheetPage.image(of: try SheetPDFFactory.pdf([]), width: 800))
        #expect(small.width == 800)
    }
}

/// Vision itself, on a page with large clear text. It needs no window, but may need a desktop session.
@Suite(.enabled(if: CGSessionCopyCurrentDictionary() != nil, "Text recognition needs a desktop session"))
struct VisionTextRecognizerTests {
    @Test func printedTextIsRecognizedWhereItIs() async throws {
        let pdf = try SheetPDFFactory.pdf([PlacedText("XP Gained", 0.3, 0.3), PlacedText("Total XP", 0.3, 0.6)])
        let image = try #require(SheetPage.image(of: pdf))
        let lines = try await VisionTextRecognizer().lines(in: image)
        let upper = try #require(lines.first { $0.text.contains("XP Gained") })
        let lower = try #require(lines.first { $0.text.contains("Total XP") })
        #expect(upper.box.minY < lower.box.minY)
        #expect(abs(upper.box.minY - 0.3) < 0.03)
    }
}
