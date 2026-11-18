import Foundation
import SwiftSoup

/// Reads the boons the player has from the Boons tab of My Organized Play: the table under "Boons you have
/// purchased", one row per boon with a link to its PDF. The purchase forms above it are ignored.
public enum BoonsPageParser {
    public static func boons(in html: String, base: URL) throws -> [Boon] {
        let document = try parseDocument(html, operation: "Reading the Boons tab")
        guard let table = try document.select("table").array().first(where: isBoonTable) else { return [] }
        return try table.select("tr").array().compactMap { try boon(in: $0, base: base) }
    }

    private static func isBoonTable(_ table: Element) -> Bool {
        let headers = (try? table.select("th").array().map { try $0.text() }) ?? []
        return Array(headers.prefix(4)) == ["Character", "Name", "Description", "Quantity"]
    }

    private static func boon(in row: Element, base: URL) throws -> Boon? {
        let cells = row.children().array().filter { $0.tagName() == "td" }
        guard cells.count >= 7, let link = try cells[6].select("a[href]").first(),
              let url = URL(string: try link.attr("href"), encodingInvalidCharacters: true)
        else { return nil }
        let texts = try cells.map { try $0.text() }
        var fields = BoonFields()
        fields.characterName = texts[0]
        fields.name = texts[1]
        fields.summary = texts[2]
        fields.quantity = Int(texts[3]) ?? 1
        fields.isConsumable = texts[4].caseInsensitiveCompare("Yes") == .orderedSame
        fields.remainingUses = Int(texts[5])
        fields.downloadURL = URL(string: url.absoluteString, relativeTo: base)?.absoluteURL ?? url
        return Boon(fields: fields)
    }
}
