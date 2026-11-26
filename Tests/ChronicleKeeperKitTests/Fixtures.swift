import Foundation
@testable import ChronicleKeeperKit

/// Sanitized copies of the My Organized Play pages (fictional names, player 123456, made-up events).
enum Fixture {
    static func text(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures") else {
            throw ParsingError(operation: "Loading fixture \(name)", reason: "not in the test bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func sessionsPage1() throws -> SessionsPage {
        try SessionsPageParser.page(from: text("sessions-page1"))
    }

    static func sessionsPage2() throws -> SessionsPage {
        try SessionsPageParser.page(from: text("sessions-page2-ajax"))
    }
}

/// Builds sessions for tests that don't need a page.
enum SessionFactory {
    static func session(
        title: String = "#6-04: An Enkindled Carnival",
        summary: String = "A Pathfinder Society Scenario designed for 1st- through 4th-level characters",
        points: SessionPoints = SessionPoints(achievementPoints: 4, gmCredits: 0, campaign: .pathfinder2),
        reputation: Double? = 4,
        date: Date? = Date(timeIntervalSince1970: 1_780_000_000),
        sessionNumber: Int = 1,
        eventCode: String = "1234",
        characterName: String = "Valeria Stonebrook",
        playerNumber: String = "123456-2001"
    ) -> PlayedSession {
        var fields = PlayedSessionFields()
        fields.date = date
        // One product per title, as on paizo.com.
        fields.adventure = AdventureReference(productID: "product \(title)", title: title, summary: summary)
        fields.points = points
        fields.eventCode = eventCode
        fields.sessionNumber = sessionNumber
        fields.playerNumber = playerNumber
        fields.characterName = characterName
        fields.reputation = reputation
        fields.isGameMaster = points.gmCredits > 0
        return PlayedSession(fields: fields)
    }
}
