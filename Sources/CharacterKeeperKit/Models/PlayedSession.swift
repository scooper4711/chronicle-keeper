import Foundation

/// An adventure as a session row links to it.
public struct AdventureReference: Hashable, Codable, Sendable {
    /// Paizo's product ID from the product link ("btq0e8yu"), or empty when the row has no link.
    public let productID: String
    public let title: String
    /// The product link's description, which says what kind of adventure it is and its levels.
    public let summary: String

    public init(productID: String, title: String, summary: String) {
        self.productID = productID
        self.title = title
        self.summary = summary
    }
}

/// The Points column: Achievement Points and GM credit.
public struct SessionPoints: Hashable, Codable, Sendable {
    public let achievementPoints: Double
    public let gmCredits: Double
    /// The campaign the Achievement Points are for ("Achievement Points - PFS(2ed)").
    public let campaign: Campaign

    public init(achievementPoints: Double, gmCredits: Double, campaign: Campaign) {
        self.achievementPoints = achievementPoints
        self.gmCredits = gmCredits
        self.campaign = campaign
    }
}

/// One row of the Sessions tab: a session that applied to one of the player's characters.
public struct PlayedSession: Hashable, Codable, Sendable, Identifiable {
    public let date: Date?
    public let gameMaster: String
    public let adventure: AdventureReference
    public let points: SessionPoints
    public let eventCode: String
    public let eventName: String
    public let sessionNumber: Int
    /// "123456-2001" on a played session; only "123456" when the player was the GM.
    public let playerNumber: String
    public let characterName: String
    /// The faction the session's reputation went to, or empty when the site shows "—".
    public let faction: String
    /// The reputation earned, or nil when the site shows "—".
    public let reputation: Double?
    /// True when the player ran this session and applied the credit to the character.
    public let isGameMaster: Bool
    public let notes: String

    public var id: String { "\(eventCode)#\(sessionNumber)#\(characterName)" }

    /// The character number when the row names one (played sessions only).
    public var characterNumber: String? {
        playerNumber.contains("-") ? playerNumber : nil
    }

    public var campaign: Campaign { points.campaign }

    public init(fields: PlayedSessionFields) {
        date = fields.date
        gameMaster = fields.gameMaster
        adventure = fields.adventure
        points = fields.points
        eventCode = fields.eventCode
        eventName = fields.eventName
        sessionNumber = fields.sessionNumber
        playerNumber = fields.playerNumber
        characterName = fields.characterName
        faction = fields.faction
        reputation = fields.reputation
        isGameMaster = fields.isGameMaster
        notes = fields.notes
    }
}

/// The values a `PlayedSession` is made from, so that it can be built field by field.
public struct PlayedSessionFields: Sendable {
    public var date: Date?
    public var gameMaster = ""
    public var adventure = AdventureReference(productID: "", title: "", summary: "")
    public var points = SessionPoints(achievementPoints: 0, gmCredits: 0, campaign: .other(""))
    public var eventCode = ""
    public var eventName = ""
    public var sessionNumber = 0
    public var playerNumber = ""
    public var characterName = ""
    public var faction = ""
    public var reputation: Double?
    public var isGameMaster = false
    public var notes = ""

    public init() {}
}
