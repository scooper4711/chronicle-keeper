import CoreGraphics
import Foundation

/// A line of text on a chronicle sheet and where it is: from the PDF's own text, or from text recognition.
public struct RecognizedLine: Hashable, Sendable {
    public let text: String
    /// In fractions of the page, with `y` measured from the top: a smaller `y` is higher on the sheet.
    public let box: CGRect

    public init(text: String, box: CGRect) {
        self.text = text
        self.box = box
    }

    /// The text in lower case with its runs of spaces made one and soft hyphens dropped, for comparing.
    var plainText: String {
        text.replacingOccurrences(of: "\u{00AD}", with: "")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// Whether the line runs up the page, as the names along a sheet's reward column do. A letter or two is
    /// taller than wide without being that.
    var isVertical: Bool {
        text.count >= 4 && box.height * SheetPageShape.height > box.width * SheetPageShape.width * 1.5
    }
}

/// The shape of a chronicle sheet's page, a letter-size sheet in points: fractions of its width and of its height
/// aren't the same length.
enum SheetPageShape {
    static let width: CGFloat = 603
    static let height: CGFloat = 783
}
