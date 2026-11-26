import Foundation

/// A fictional account for trying the app without signing in, for App Review, screenshots and UI tests.
/// Every name, number, event and adventure title here is made up.
public enum DemoAccount {
    public static let playerNumber = "123456"

    public static func snapshot(fetchedAt: Date = Date(timeIntervalSince1970: 1_795_000_000)) -> AccountSnapshot {
        AccountSnapshot(characters: characters, sessions: sessions, boons: DemoBoons.boons, fetchedAt: fetchedAt)
    }

    static let characters: [CharacterSummary] = [
        CharacterSummary(
            number: "\(playerNumber)-2001", campaign: .pathfinder2, name: "Valeria Stonebrook",
            factions: [NamedValue(name: "Envoy's Alliance", value: 14), NamedValue(name: "Horizon Hunters", value: 22)],
            standing: [NamedValue(name: "Fame", value: 41)]),
        CharacterSummary(
            number: "\(playerNumber)-2002", campaign: .pathfinder2, name: "Pip Underbough",
            factions: [NamedValue(name: "Grand Archive", value: 6)], standing: [NamedValue(name: "Fame", value: 9)]),
        CharacterSummary(
            number: "\(playerNumber)-2003", campaign: .pathfinder2, name: "Morrow Ashgrove",
            factions: [], standing: [NamedValue(name: "Fame", value: 0)]),
        CharacterSummary(
            number: "\(playerNumber)-2004", campaign: .pathfinder2, name: "Zenobia Everbright",
            factions: [
                NamedValue(name: "Envoy's Alliance", value: 31), NamedValue(name: "Grand Archive", value: 27),
                NamedValue(name: "Horizon Hunters", value: 64), NamedValue(name: "Radiant Oath", value: 18),
                NamedValue(name: "Verdant Wheel", value: 40), NamedValue(name: "Vigilant Seal", value: 23)],
            standing: [NamedValue(name: "Fame", value: 203)]),
        CharacterSummary(
            number: "\(playerNumber)-1301", campaign: .pathfinder1, name: "Bartholomew Quillfeather",
            factions: [
                NamedValue(name: "Dark Archive", value: 12), NamedValue(name: "Grand Lodge", value: 9),
                NamedValue(name: "Lantern Lodge", value: 15), NamedValue(name: "Liberty's Edge", value: 7),
                NamedValue(name: "Scarab Sages", value: 20), NamedValue(name: "Sczarni", value: 4),
                NamedValue(name: "Shadow Lodge", value: 11), NamedValue(name: "Silver Crusade", value: 18),
                NamedValue(name: "Sovereign Court", value: 6), NamedValue(name: "The Exchange", value: 13)],
            standing: [NamedValue(name: "Fame", value: 115)]),
        CharacterSummary(
            number: "\(playerNumber)-801", campaign: .starfinder1, name: "Kessa Brightwater",
            factions: [
                NamedValue(name: "Acquisitives", value: 10), NamedValue(name: "Dataphiles", value: 14),
                NamedValue(name: "Exo-Guardians", value: 8), NamedValue(name: "Second Seekers", value: 16),
                NamedValue(name: "Wayfinders", value: 12)],
            standing: [NamedValue(name: "Total Reputation", value: 60)]),
        CharacterSummary(
            number: "\(playerNumber)-701", campaign: .starfinder2, name: "Zix-7", factions: [], standing: []),
        CharacterSummary(
            number: "\(playerNumber)-702", campaign: .starfinder2, name: "Captain Oreth Vane",
            factions: [], standing: [])
    ]

    static var sessions: [PlayedSession] {
        valeriaSessions + pipSessions + starfinderSessions
    }

    private static var valeriaSessions: [PlayedSession] {
        let who = DemoCharacter(number: "\(playerNumber)-2001", name: "Valeria Stonebrook")
        return [
            DemoAdventure.scenario("#6-02: The Lantern Fair", levels: "1st- through 4th"),
            DemoAdventure.scenario("#6-05: Ashes Over Highhelm", levels: "1st- through 4th"),
            DemoAdventure.quest("Pathfinder Quest (Series 2) #15: The Missing Bell"),
            DemoAdventure.scenario("#6-09: Tides of the Glass Sea", levels: "3rd- through 6th"),
            DemoAdventure.bounty("Pathfinder Bounty #21: The Clockwork Hound"),
            DemoAdventure.scenario("#6-12: Beneath the Ninth Arch", levels: "3rd- through 6th"),
            // A Chronicle Paizo's "Applying Credit" rules held until she reached the pregen's level: shown with
            // an asterisk, since level 2 falls outside this adventure's 7th- through 10th-level range.
            DemoAdventure.scenario("#6-20: The Severed Stars", levels: "7th- through 10th")
        ].enumerated().map { index, adventure in
            adventure.session(for: who, number: index + 1, daysAgo: 300 - index * 40, campaign: .pathfinder2)
        }
    }

    private static var pipSessions: [PlayedSession] {
        let who = DemoCharacter(number: "\(playerNumber)-2002", name: "Pip Underbough")
        let slow = DemoAdventure.scenario("#6-02: The Lantern Fair", levels: "1st- through 4th", reputation: 2)
        let credit = DemoAdventure.scenario("#6-07: A Feast for Crows", levels: "1st- through 4th", isCredit: true)
        return [
            slow.session(for: who, number: 7, daysAgo: 120, campaign: .pathfinder2),
            credit.session(for: DemoCharacter(number: playerNumber, name: who.name), number: 8, daysAgo: 60,
                           campaign: .pathfinder2)
        ]
    }

    private static var starfinderSessions: [PlayedSession] {
        let zix = DemoCharacter(number: "\(playerNumber)-701", name: "Zix-7")
        let oreth = DemoCharacter(number: "\(playerNumber)-702", name: "Captain Oreth Vane")
        let first = DemoAdventure.starfinder("SFS2 #1-03: Static on the Drift")
        let second = DemoAdventure.starfinder("SFS2 #1-06: The Hollow Moon")
        return [
            first.session(for: zix, number: 9, daysAgo: 200, campaign: .starfinder2),
            second.session(for: zix, number: 10, daysAgo: 30, campaign: .starfinder2),
            first.session(for: oreth, number: 11, daysAgo: 90, campaign: .starfinder2)
        ]
    }
}

private struct DemoCharacter {
    let number: String
    let name: String
}

/// One made-up adventure, and how a session of it went.
private struct DemoAdventure {
    let title: String
    let summary: String
    let achievementPoints: Double
    let reputation: Double?
    var isCredit = false

    static func scenario(
        _ title: String, levels: String, reputation: Double = 4, isCredit: Bool = false
    ) -> DemoAdventure {
        DemoAdventure(
            title: title, summary: "A Pathfinder Society Scenario designed for \(levels)-level characters",
            achievementPoints: 4, reputation: reputation, isCredit: isCredit)
    }

    static func quest(_ title: String) -> DemoAdventure {
        DemoAdventure(
            title: title, summary: "A Pathfinder Society Quest designed for 1st- through 4th-level characters",
            achievementPoints: 2, reputation: 2)
    }

    static func bounty(_ title: String) -> DemoAdventure {
        DemoAdventure(
            title: title, summary: "A Pathfinder Bounty designed for 1st-level characters",
            achievementPoints: 2, reputation: 1)
    }

    static func starfinder(_ title: String) -> DemoAdventure {
        DemoAdventure(
            title: title, summary: "A Starfinder Society Scenario designed for 1st- through 4th-level characters",
            achievementPoints: 4, reputation: nil)
    }

    /// Stable across launches, and the same for every session of this adventure.
    var productID: String {
        "demo-" + String(title.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(24))
    }

    func session(for character: DemoCharacter, number: Int, daysAgo: Int, campaign: Campaign) -> PlayedSession {
        var fields = PlayedSessionFields()
        fields.date = Date(timeIntervalSince1970: 1_795_000_000 - Double(daysAgo) * 86_400)
        fields.gameMaster = isCredit ? "Demo Player" : "Imaginary GM"
        fields.adventure = AdventureReference(productID: productID, title: title, summary: summary)
        fields.points = SessionPoints(achievementPoints: achievementPoints, gmCredits: isCredit ? 1 : 0,
                                      campaign: campaign)
        fields.eventCode = "900\(number)"
        fields.eventName = "Demo Game Day"
        fields.sessionNumber = number
        fields.playerNumber = character.number
        fields.characterName = character.name
        fields.reputation = reputation
        fields.isGameMaster = isCredit
        return PlayedSession(fields: fields)
    }
}
