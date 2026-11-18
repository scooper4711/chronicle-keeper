import Foundation
import SwiftSoup

/// "51 to 77 of 77": the rows a Sessions page shows.
public struct PageRange: Hashable, Sendable {
    public let first: Int
    public let last: Int
    public let total: Int

    public var isLastPage: Bool { last >= total }
}

/// The "next >" link of a Sessions page: an Ajax component URL and the update container it refreshes.
public struct NextPageLink: Hashable, Sendable {
    public let path: String
    public let containerID: String
}

/// One page of the Sessions tab, or the Ajax fragment that replaces it.
public struct SessionsPage: Sendable {
    public let sessions: [PlayedSession]
    public let range: PageRange?
    public let nextPage: NextPageLink?
}

/// Reads the Sessions tab of My Organized Play.
public enum SessionsPageParser {
    public static func page(from html: String) throws -> SessionsPage {
        let document = try parseDocument(html, operation: "Reading a Sessions page")
        let rows = try document.select("tr").array().filter(isSessionRow)
        return SessionsPage(
            sessions: try rows.map(SessionRowParser.session(in:)),
            range: try range(in: document),
            nextPage: try nextPage(in: document)
        )
    }

    /// Session rows have 13 cells, the fourth holding the points.
    private static func isSessionRow(_ row: Element) -> Bool {
        let cells = row.children().array().filter { $0.tagName() == "td" }
        guard cells.count == 13, let points = try? cells[3].text() else { return false }
        return points.contains("Achievement Points") || points.contains("GM Credits") || points.contains("Prestige")
    }

    private static func range(in document: Document) throws -> PageRange? {
        let text = try document.text()
        guard let match = text.firstMatch(of: /(\d+)\s+to\s+(\d+)\s+of\s+(\d+)/) else { return nil }
        return PageRange(first: Int(match.1) ?? 0, last: Int(match.2) ?? 0, total: Int(match.3) ?? 0)
    }

    private static func nextPage(in document: Document) throws -> NextPageLink? {
        let links = try document.select("a").array()
        guard let link = try links.first(where: { try $0.text() == "next >" }) else { return nil }
        let onclick = try link.attr("onclick")
        guard let match = onclick.firstMatch(of: /AUL\.update\('([^']+)'/) else {
            throw ParsingError(operation: "Reading a Sessions page", reason: "the next-page link has no Ajax target")
        }
        return NextPageLink(path: try link.attr("href"), containerID: String(match.1))
    }
}
