import CoreGraphics
import Foundation
import PDFKit

/// The lines of text a chronicle sheet's PDF holds itself: what a program wrote on its first page, and the values
/// of form fields filled in. A sheet made for online play is read from these, exactly and at once; a scanned
/// sheet has none (design.md, "Reading a chronicle sheet").
public enum PDFTextLines {
    public static func lines(of pdf: Data) -> [RecognizedLine] {
        guard let page = PDFDocument(data: pdf)?.page(at: 0) else { return [] }
        return runs(on: page) + formValues(on: page)
    }

    /// The page's text as runs of words on one line with no wide gap between them. PDFKit's own lines run the
    /// whole width of the page, which would join a label to the text beside it.
    private static func runs(on page: PDFPage) -> [RecognizedLine] {
        var runs: [Run] = []
        for word in words(on: page) {
            if let last = runs.indices.last, !word.startsALine, runs[last].continues(with: word.bounds) {
                runs[last].append(word.text, word.bounds)
            } else {
                runs.append(Run(text: word.text, bounds: word.bounds))
            }
        }
        return runs.map { RecognizedLine(text: $0.text, box: unitBox(of: $0.bounds, on: page)) }
    }

    /// Each word of the page's text with where it is, in reading order. A word's place is asked of a selection of
    /// it: `characterBounds(at:)` counts characters differently from `string`, which has line breaks in it.
    private static func words(on page: PDFPage) -> [Word] {
        let text = (page.string ?? "") as NSString
        var words: [Word] = []
        var startsALine = true
        var location = 0
        while let range = nextWord(in: text, from: location) {
            let gap = text.substring(with: NSRange(location: location, length: range.location - location))
            startsALine = startsALine || gap.contains(where: \.isNewline)
            if let bounds = page.selection(for: range)?.bounds(for: page), bounds.height > 0 {
                words.append(Word(text: text.substring(with: range), bounds: bounds, startsALine: startsALine))
                startsALine = false
            }
            location = range.location + range.length
        }
        return words
    }

    /// The next run of characters that aren't spaces or line breaks, at or after `location`.
    private static func nextWord(in text: NSString, from location: Int) -> NSRange? {
        let rest = NSRange(location: location, length: text.length - location)
        let start = text.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted, range: rest).location
        guard start != NSNotFound else { return nil }
        let after = NSRange(location: start, length: text.length - start)
        let end = text.rangeOfCharacter(from: .whitespacesAndNewlines, range: after).location
        return NSRange(location: start, length: (end == NSNotFound ? text.length : end) - start)
    }

    private static func formValues(on page: PDFPage) -> [RecognizedLine] {
        page.annotations.compactMap { annotation in
            guard annotation.type == "Widget", let value = annotation.widgetStringValue,
                  !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return RecognizedLine(text: value, box: unitBox(of: annotation.bounds, on: page))
        }
    }

    /// A box in the page's own points, as fractions of the page the way up it is shown, `y` from the top.
    static func unitBox(of box: CGRect, on page: PDFPage) -> CGRect {
        let media = page.bounds(for: .mediaBox)
        guard media.width > 0, media.height > 0 else { return .zero }
        let left = (box.minX - media.minX) / media.width
        let top = (media.maxY - box.maxY) / media.height
        let upright = CGRect(x: left, y: top, width: box.width / media.width, height: box.height / media.height)
        return turned(upright, by: page.rotation)
    }

    /// The box where a page turned clockwise by `degrees` shows it.
    static func turned(_ box: CGRect, by degrees: Int) -> CGRect {
        switch ((degrees % 360) + 360) % 360 {
        case 90: CGRect(x: 1 - box.maxY, y: box.minX, width: box.height, height: box.width)
        case 180: CGRect(x: 1 - box.maxX, y: 1 - box.maxY, width: box.width, height: box.height)
        case 270: CGRect(x: box.minY, y: 1 - box.maxX, width: box.height, height: box.width)
        default: box
        }
    }
}

/// A word of a page's text.
private struct Word {
    let text: String
    let bounds: CGRect
    /// Whether the page's text has a line break before it.
    let startsALine: Bool
}

/// Words that follow each other on one line.
private struct Run {
    var text: String
    var bounds: CGRect

    /// Whether a word is on this run's line and starts close to where the run ends: within a wide space.
    func continues(with word: CGRect) -> Bool {
        let isOnTheLine = abs(word.midY - bounds.midY) < bounds.height / 2
        let gap = word.minX - bounds.maxX
        return isOnTheLine && gap < 0.9 * bounds.height && gap > -bounds.height
    }

    mutating func append(_ word: String, _ wordBounds: CGRect) {
        text += " " + word
        bounds = bounds.union(wordBounds)
    }
}
