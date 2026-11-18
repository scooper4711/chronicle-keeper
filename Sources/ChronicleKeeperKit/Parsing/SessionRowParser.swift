import Foundation
import SwiftSoup

/// Reads one 13-cell row of the Sessions table:
/// Date | GM | Scenario | Points | Event code | Event | Session | Player | Character | Faction | Rep | Notes | Edit
enum SessionRowParser {
    static func session(in row: Element) throws -> PlayedSession {
        let cells = row.children().array().filter { $0.tagName() == "td" }
        var fields = PlayedSessionFields()
        fields.date = try date(in: cells[0])
        fields.gameMaster = try cells[1].text()
        fields.adventure = try adventure(in: cells[2])
        fields.points = try PointsParser.points(in: cells[3].html())
        fields.eventCode = try cells[4].text()
        fields.eventName = try cells[5].text()
        fields.sessionNumber = Int(try cells[6].text()) ?? 0
        fields.playerNumber = try cells[7].text()
        fields.characterName = try cells[8].text()
        fields.faction = dashMeansEmpty(try cells[9].text())
        let reputation = ReputationText(try cells[10].text())
        fields.reputation = reputation.value
        fields.isGameMaster = reputation.isGameMaster || fields.points.gmCredits > 0
        fields.notes = try cells[11].text()
        return PlayedSession(fields: fields)
    }

    private static func date(in cell: Element) throws -> Date? {
        let stamp = try cell.select("time").first()?.attr("datetime") ?? ""
        return stamp.isEmpty ? nil : ISO8601DateFormatter().date(from: stamp)
    }

    private static func adventure(in cell: Element) throws -> AdventureReference {
        guard let link = try cell.select("a").first() else {
            return AdventureReference(productID: "", title: try cell.text(), summary: "")
        }
        let href = try link.attr("href")
        let productID = href.firstMatch(of: /\/products\/([A-Za-z0-9]+)/).map { String($0.1) } ?? ""
        return AdventureReference(productID: productID, title: try link.text(), summary: try link.attr("title"))
    }

    private static func dashMeansEmpty(_ text: String) -> String {
        text == "—" || text == "-" ? "" : text
    }
}

/// The Prest. / Rep. column: "4", "GM 4", "—".
struct ReputationText {
    let value: Double?
    let isGameMaster: Bool

    init(_ text: String) {
        isGameMaster = text.hasPrefix("GM")
        let number = text.replacingOccurrences(of: "GM", with: "").trimmingCharacters(in: .whitespaces)
        value = Double(number)
    }
}

/// The Points column: lines such as "6.00 Achievement Points - PFS(2ed)" and
/// "1.00 Pathfinder Society (second edition) GM Credits", separated by `<br>`.
enum PointsParser {
    static func points(in html: String) throws -> SessionPoints {
        let lines = try html.split(separator: /<br\s*\/?>/).map { try SwiftSoup.parseBodyFragment(String($0)).text() }
        var acp = 0.0, credits = 0.0
        var campaign = Campaign.other("")
        for line in lines {
            if let match = line.firstMatch(of: /^([\d.]+) Achievement Points - (.+)$/) {
                acp += Double(match.1) ?? 0
                campaign = Campaign(code: String(match.2))
            } else if let match = line.firstMatch(of: /^([\d.]+) (.+) GM Credits$/) {
                credits += Double(match.1) ?? 0
                if case .other = campaign { campaign = campaignFromCreditName(String(match.2)) }
            }
        }
        return SessionPoints(achievementPoints: acp, gmCredits: credits, campaign: campaign)
    }

    private static func campaignFromCreditName(_ name: String) -> Campaign {
        let isStarfinder = name.contains("Starfinder")
        let isSecond = name.contains("second edition")
        switch (isStarfinder, isSecond) {
        case (true, true): return .starfinder2
        case (true, false): return .starfinder1
        case (false, true): return .pathfinder2
        case (false, false): return .pathfinder1
        }
    }
}
