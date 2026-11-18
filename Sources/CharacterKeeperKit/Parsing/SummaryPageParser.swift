import Foundation
import SwiftSoup

/// Reads the characters from the Summary tab of My Organized Play.
public enum SummaryPageParser {
    public static func characters(in html: String) throws -> [CharacterSummary] {
        let document = try parseDocument(html, operation: "Reading the Summary page")
        return try document.select("tr").array().compactMap(character(in:))
    }

    private static func character(in row: Element) throws -> CharacterSummary? {
        let cells = row.children().array().filter { $0.tagName() == "td" }
        guard cells.count >= 4 else { return nil }
        let numberText = try cells[0].text()
        guard let match = numberText.firstMatch(of: /^#\s*(\d+-\d+)$/) else { return nil }
        let (factions, standing) = try values(in: cells[3])
        return CharacterSummary(
            number: String(match.1),
            campaign: Campaign(code: try cells[1].text()),
            name: try cells[2].text(),
            factions: factions,
            standing: standing
        )
    }

    /// "Horizon Hunters: 68", "Fame: 89", each in its own `nobr`.
    private static func values(in cell: Element) throws -> ([NamedValue], [NamedValue]) {
        let pairs = try cell.select("nobr").array().compactMap { namedValue(try $0.text()) }
        let standing = pairs.filter { standingNames.contains($0.name) }
        return (pairs.filter { !standingNames.contains($0.name) }, standing)
    }

    private static func namedValue(_ text: String) -> NamedValue? {
        guard let match = text.firstMatch(of: /^(.+?):\s*(-?\d+)$/) else { return nil }
        return NamedValue(name: String(match.1), value: Int(match.2) ?? 0)
    }

    private static let standingNames: Set<String> = ["Fame", "Total Reputation", "Prestige", "Total Prestige"]
}

func parseDocument(_ html: String, operation: String) throws -> Document {
    do {
        return try SwiftSoup.parse(html)
    } catch {
        throw ParsingError(operation: operation, reason: "the HTML could not be read (\(error))")
    }
}
