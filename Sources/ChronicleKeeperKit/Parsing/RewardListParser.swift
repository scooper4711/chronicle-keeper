import Foundation
import SwiftSoup

/// A link the site's own script follows with an Ajax update: the component URL and the container it refreshes, as in
/// `<a href="/…/ajax/…" onclick="AUL.update('_2', {}, '…');return false;">`.
public struct AjaxLink: Hashable, Sendable {
    public let path: String
    public let containerID: String

    public init(path: String, containerID: String) {
        self.path = path
        self.containerID = containerID
    }

    /// Nil for a link that isn't an Ajax update.
    init?(_ link: Element) {
        guard let onclick = try? link.attr("onclick"), let path = try? link.attr("href"), !path.isEmpty,
              let match = onclick.firstMatch(of: /AUL\.update\('([^']+)'/) else { return nil }
        self.init(path: path, containerID: String(match.1))
    }
}

/// One of the Boons tab's "Rewards purchaseable with … (click to expand)" links, for a list of free rewards.
public struct RewardListLink: Hashable, Sendable {
    public let type: RewardPointType
    /// The point type as the page words it, for messages.
    public let title: String
    public let link: AjaxLink
}

/// Reads the free reward lists of the Boons tab: the links that open them, and the table each opens to.
public enum RewardListParser {
    /// The links to the lists of free rewards. The lists that cost points are left out; a page without any list (an
    /// account with no character in these campaigns) has none.
    public static func links(in html: String) throws -> [RewardListLink] {
        let document = try parseDocument(html, operation: "Reading the Boons tab")
        return try document.select("a").array().compactMap(listLink)
    }

    private static func listLink(_ element: Element) throws -> RewardListLink? {
        let text = try element.text()
        guard let match = text.firstMatch(of: /Rewards purchaseable with (.+?) \(click to expand\)/),
              let type = RewardPointType(String(match.1)) else { return nil }
        guard let link = AjaxLink(element) else {
            throw ParsingError(operation: "Reading the Boons tab",
                               reason: "the link to the list of \(match.1) has no Ajax target")
        }
        return RewardListLink(type: type, title: String(match.1), link: link)
    }

    /// The rewards of an opened list: the rows of the table headed "Name | Description | Price | Point Type". Rows
    /// that cost points, or of another point type, are left out.
    public static func offers(in html: String, list: String) throws -> [RewardOffer] {
        let operation = "Reading the list of \(list)"
        let document = try parseDocument(html, operation: operation)
        guard let table = try document.select("table").array().first(where: isRewardTable) else {
            throw ParsingError(operation: operation, reason: "the list has no table of rewards")
        }
        return try table.select("tr").array().compactMap(offer)
    }

    /// The page's layout table holds the reward tables, so a table counts only by its own first row.
    private static func isRewardTable(_ table: Element) -> Bool {
        guard let header = try? table.select("tr").first() else { return false }
        let titles = header.children().array().filter { $0.tagName() == "th" }.compactMap { try? $0.text() }
        return Array(titles.prefix(4)) == ["Name", "Description", "Price", "Point Type"]
    }

    private static func offer(in row: Element) throws -> RewardOffer? {
        let cells = try row.children().array().filter { $0.tagName() == "td" }.map { try $0.text() }
        guard cells.count >= 4, Double(cells[2]) == 0, let type = RewardPointType(cells[3]), !cells[0].isEmpty
        else { return nil }
        return RewardOffer(type: type, name: cells[0], summary: cells[1])
    }
}
