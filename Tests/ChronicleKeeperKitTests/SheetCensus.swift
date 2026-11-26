import CoreGraphics
import Foundation
import Testing
@testable import ChronicleKeeperKit

/// The census of chronicle sheet formats (`Fixtures/chronicle-formats.json`, written by
/// `scripts/chronicle-format-census.py`): for every Pathfinder Society and Starfinder Society (second edition)
/// chronicle, its own printing and where its layout writes each value.
struct SheetCensus: Decodable {
    let sheets: [Sheet]

    struct Sheet: Decodable, CustomTestStringConvertible {
        /// "pfs2/season5/5-11-…Chronicle".
        let sheet: String
        /// The code its file name gives it, or nil for one that has none.
        let code: String?
        let printed: [PrintedLine]
        /// Where the layout writes "xp", "funds", "player", "character" and "eventCode"; nil when the layout
        /// was made for another sheet's positions, or the sheet's labels aren't text.
        let values: [String: [Double]]?

        var testDescription: String { sheet }

        var lines: [RecognizedLine] { printed.map(\.line) }

        func box(of value: String) -> CGRect? {
            values?[value].map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
        }

        func label(_ label: SheetLabel) -> RecognizedLine? {
            lines.first { SheetLabel.of($0) == label }
        }
    }

    /// One printed line, saved as `[text, x, y, width, height]`.
    struct PrintedLine: Decodable {
        let line: RecognizedLine

        init(from decoder: Decoder) throws {
            var parts = try decoder.unkeyedContainer()
            let text = try parts.decode(String.self)
            let numbers = try (0..<4).map { _ in try parts.decode(Double.self) }
            line = RecognizedLine(
                text: text, box: CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]))
        }
    }

    static let all: [Sheet] = {
        guard let url = Bundle.module.url(
            forResource: "chronicle-formats", withExtension: "json", subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url),
              let census = try? JSONDecoder().decode(SheetCensus.self, from: data) else { return [] }
        return census.sheets
    }()

    /// The sheets whose layout says where each value goes.
    static let withValues = all.filter { $0.values != nil }
}

/// Builds the lines a filled-in sheet would give.
enum SheetLineFactory {
    /// A line written in the middle of a box, as wide as its text.
    static func written(_ text: String, in box: CGRect) -> RecognizedLine {
        let width = CGFloat(text.count) * 0.009
        return RecognizedLine(
            text: text, box: CGRect(x: box.midX - width / 2, y: box.midY - 0.006, width: width, height: 0.012))
    }

    static func line(_ text: String, left: CGFloat, top: CGFloat, width: CGFloat = 0.06) -> RecognizedLine {
        RecognizedLine(text: text, box: CGRect(x: left, y: top, width: width, height: 0.012))
    }
}
