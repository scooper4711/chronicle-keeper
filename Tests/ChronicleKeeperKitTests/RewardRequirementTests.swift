import Foundation
import Testing
@testable import ChronicleKeeperKit

/// The free reward lists as paizo.com had them on 2026-11-26: each reward's name and its condition, by list.
enum RewardConditions {
    static func offers() throws -> [RewardOffer] {
        let url = try #require(Bundle.module.url(
            forResource: "reward-conditions", withExtension: "txt", subdirectory: "Fixtures"))
        var type: RewardPointType?
        var offers: [RewardOffer] = []
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            if line.hasPrefix("## ") {
                type = RewardPointType(String(line.dropFirst(3)))
            } else if !line.hasPrefix("#"), let type, let bar = line.firstRange(of: " ¦") {
                let condition = line[bar.upperBound...].trimmingCharacters(in: .whitespaces)
                offers.append(RewardOffer(type: type, name: String(line[..<bar.lowerBound]), summary: condition))
            }
        }
        return offers
    }

    static func offer(named name: String) throws -> RewardOffer {
        try #require(try offers().first { $0.name == name }, "no reward named \(name)")
    }

    static func requirement(of name: String) throws -> RewardRequirement {
        RewardRequirementParser.requirement(of: try offer(named: name))
    }
}

extension RewardRequirement {
    /// The adventures a `.played` requirement names; empty for another kind.
    var adventures: [RewardAdventure] {
        if case .played(let adventures, _) = self { return adventures }
        return []
    }

    var kindName: String {
        switch self {
        case .played: "played"
        case .reputation: "reputation"
        case .sessions: "sessions"
        case .unknown: "unknown"
        }
    }
}

@Suite("Reward requirements, read from the real lists")
struct RewardRequirementTests {
    @Test("The fixture holds the four lists whole")
    func theFixtureIsWhole() throws {
        let offers = try RewardConditions.offers()
        #expect(offers.count == 333)
        #expect(offers.filter { $0.kind == .chronicleBoon && $0.campaign == .pathfinder2 }.count == 195)
        #expect(offers.filter { $0.kind == .gameReward && $0.campaign == .pathfinder2 }.count == 25)
        #expect(offers.filter { $0.kind == .chronicleBoon && $0.campaign == .starfinder1 }.count == 93)
        #expect(offers.filter { $0.kind == .gameReward && $0.campaign == .starfinder1 }.count == 20)
    }

    @Test("Every row reads as one kind of requirement, and only the uncheckable ones are unknown")
    func census() throws {
        let offers = try RewardConditions.offers()
        let requirements = offers.map(RewardRequirementParser.requirement)
        let counts = Dictionary(grouping: requirements, by: \.kindName).mapValues(\.count)
        #expect(counts == ["played": 289, "reputation": 39, "sessions": 1, "unknown": 4])
        let unknown = zip(offers, requirements).filter { $0.1 == .unknown }.map(\.0.name)
        #expect(unknown == [
            "Companions of the Stolen Lands", "Starfinder Forum Member (Fleeting Truth)", "Awakened from Rel-State",
            "Grifter"
        ])
    }

    @Test("Every adventure a row names has a code or a title to go by")
    func everyAdventureCanBeLookedFor() throws {
        let requirements = try RewardConditions.offers().map(RewardRequirementParser.requirement)
        let adventures = requirements.flatMap(\.adventures)
        #expect(adventures.allSatisfy { !$0.code.isEmpty || !$0.nameKeys.isEmpty })
        #expect(adventures.filter { !$0.code.isEmpty }.count == 101)
    }

    @Test("A Chronicle Boon without a condition is named after its adventure", arguments: [
        ("PFS (2ed) Scenario #1–03: Escaping the Grave", "1-03"),
        ("PFS (2ed) Scenario #1–04: Bandits of Immenwood Boon A", "1-04"),
        ("PFS (2ed) Scenario #1-04: Bandits of Immenwood Boon B", "1-04"),
        ("PFS (2ed) Quest #2: Unforgiving Fire Boon B", "Quest 2"),
        ("PFS (2ed) Quest #12: Putrid Seeds", "Quest 12")
    ])
    func namedAfterItsNumberedAdventure(name: String, code: String) throws {
        let requirement = try RewardConditions.requirement(of: name)
        #expect(requirement.adventures.map(\.code) == [code])
    }

    @Test("An adventure without a number goes by its title, without the boon's letter")
    func namedAfterItsTitledAdventure() throws {
        let module = try RewardConditions.requirement(of: "Pathfinder Module: The Fall of Plaguestone Boon B")
        #expect(module.adventures == [RewardAdventure(titles: ["Pathfinder Module: The Fall of Plaguestone"])])
        let volume = try RewardConditions.requirement(
            of: "Pathfinder Adventure Path #147: Tomorrow Must Burn (Age of Ashes 3 of 6) Boon A")
        #expect(volume.adventures.map(\.code) == [""])
        #expect(volume.adventures.first?.titles == [
            "Pathfinder Adventure Path #147: Tomorrow Must Burn (Age of Ashes 3 of 6)"
        ])
        let intro = try RewardConditions.requirement(of: "PFS (2ed) Intro #1: The Second Confirmation")
        #expect(intro.adventures.first?.nameKeys == ["1secondconfirmation"])
    }

    @Test("A condition's own number is read with and without its number sign", arguments: [
        ("PFS (2ed) Scenario #3-07: Infernal Magistrix’s Blessing", "3-07"),
        ("PFS (2ed) Scenario #6-03: Is There a Doctor in the House?", "6-03"),
        ("PFS (2ed) Scenario #7-99: The Centipede Savior", "7-99"),
        ("Iceferry Lodge Gear", "1-10"),
        ("AbadarCorp Endorsement (SFS 3-00: The Last Bite)", "3-00"),
        ("Temporal Insight (Dawning Fate)", "6-16")
    ])
    func readsTheConditionsNumber(name: String, code: String) throws {
        #expect(try RewardConditions.requirement(of: name).adventures.map(\.code) == [code])
    }

    @Test("The name's number says which adventure when the condition has only a title", arguments: [
        ("PFS (2ed) Scenario #4-03: Stalwart Shield", "4-03", "Linnorm's Legacy"),
        ("PFS (2ed) Scenario #6-14: Alicorn's Blessing", "6-14", "Twice in Steel"),
        ("Planar Preparations (SFS #5-06: Tarnished Legacy: Historia’s Holdout)", "5-06",
         "Tarnished Legacy: Historia's Holdout")
    ])
    func theNamesNumberOutranksATitle(name: String, code: String, title: String) throws {
        let adventure = try #require(try RewardConditions.requirement(of: name).adventures.first)
        #expect(adventure.code == code)
        #expect(adventure.titles == [title])
    }

    @Test("A condition with only a title goes by it", arguments: [
        ("Extinction Curse: The Show Must Go On - Snare Training", ["The Show Must Go On"]),
        ("Hellbreakers: Loyal Friend", ["Hellbreakers, Part 2"]),
        ("Adventuring with Amiri", ["The Blade's Legacy"]),
        ("Stolen Fate: The Choosing–Holding Out for a Harrow", ["The Choosing (Stolen Fate #1)", "The Choosing"]),
        ("Friendly Tumbleweed (Mechageddon!)", ["Colossus Clash (part 1 of Mechageddon!)", "Colossus Clash"]),
        ("Pathfinder Adventure Path: Abomination Vaults - Ghost Hunter", ["Ruins of Gauntlight"]),
        ("Loaned Ship: Sunrise Maiden (Dead Suns Adventure Path)", ["Incident at Absalom Station"])
    ])
    func goesByTheConditionsTitle(name: String, titles: [String]) throws {
        let requirement = try RewardConditions.requirement(of: name)
        #expect(requirement == .played([RewardAdventure(titles: titles)], needsAll: false))
    }

    @Test("\"At least one\" part of a series goes by the series' name", arguments: [
        ("PFS (2ed) Adventure: Menace Under Otari (Beginner Box)", "Menace Under Otari"),
        ("Strength of Thousands - Magaambyan Attendant", "Strength of Thousands"),
        ("Year of the Scoured Stars", "Scoured Stars"),
        ("Friend to the Ghorans (Frozen Ambitions)", "Frozen Ambitions")
    ])
    func anyPartOfASeries(name: String, series: String) throws {
        let requirement = try RewardConditions.requirement(of: name)
        #expect(requirement == .played([RewardAdventure(titles: [series])], needsAll: false))
    }

    @Test("OR needs one of the adventures and AND needs each")
    func eitherAndEach() throws {
        let either = try RewardConditions.requirement(of: "Lantern Lodge Gear")
        #expect(either.adventures.map(\.code) == ["1-06", "2-02"])
        #expect(either == .played(either.adventures, needsAll: false))
        let each = try RewardConditions.requirement(of: "Open Road Lodge Gear")
        #expect(each.adventures.map(\.code) == ["1-16", "1-17"])
        #expect(each == .played(each.adventures, needsAll: true))
    }

    @Test("A status is the reputation its campaign's ladder begins it at", arguments: [
        ("Skillful Mentor (Envoy's Alliance)", 20, "Envoy's Alliance"),
        ("Heroic Hustle (Horizon Hunters)", 60, "Horizon Hunters"),
        ("Expert Hireling", 20, ""), ("Professional Hireling", 60, ""), ("Master Hireling", 120, "")
    ])
    func readsAStatus(name: String, points: Int, faction: String) throws {
        #expect(try RewardConditions.requirement(of: name) == .reputation(points: points, faction: faction))
    }

    @Test("Starfinder's conditions give the reputation as a number", arguments: [
        ("Purveyor of Fortunes (Acquisitives)", 5, "Acquisitives"),
        ("Acquisitives Champion", 15, "Acquisitives"),
        ("Seeker of Knowledge (Second Seekers: Ehu Hadif)", 5, "Second Seekers (Ehu)"),
        ("Second Seekers (Luwazi Elsebo) Champion", 15, "Second Seekers (Luwazi Elsebo)"),
        ("Manifold Host Champion", 15, "Manifold Host")
    ])
    func readsAReputationNumber(name: String, points: Int, faction: String) throws {
        #expect(try RewardConditions.requirement(of: name) == .reputation(points: points, faction: faction))
    }

    @Test("The Wayfinder takes two sessions")
    func readsASessionCount() throws {
        #expect(try RewardConditions.requirement(of: "Wayfinder") == .sessions(2))
    }

    private func offer(_ type: String, _ name: String, _ summary: String) throws -> RewardOffer {
        RewardOffer(type: try #require(RewardPointType(type)), name: name, summary: summary)
    }

    @Test("Wordings the app doesn't know are unknown, never guessed")
    func unknownWordings() throws {
        let game = "Game Rewards - PFS(2ed)", first = "Game Rewards - PFS"
        let cases = [
            try offer(game, "No Condition", "Does something useful."),
            try offer(game, "New Status", "Must be Adored by Grand Archive to obtain."),
            try offer(first, "No Ladder", "Must be Liked by Grand Lodge to obtain."),
            try offer(game, "Both", "Must have played 1-01: One OR 1-02: Two AND 1-03: Three to obtain."),
            try offer(game, "Other", "Must be a Venture-Captain to obtain."),
            try offer("Chronicle Boons - PFS(2ed)", "Other Boon", "Must complete the trial to download.")
        ]
        #expect(cases.map(RewardRequirementParser.requirement) == Array(repeating: .unknown, count: cases.count))
    }

    @Test("A number inside a word is no scenario number")
    func numbersInsideWordsAreNotCodes() {
        #expect(RewardRequirementParser.code(in: "The Liberation of Locus-1").isEmpty)
        #expect(RewardRequirementParser.code(in: "Iteration-177's Attention").isEmpty)
        #expect(RewardRequirementParser.code(in: "Pathfinder Adventure Path #146: Cult of Cinders").isEmpty)
        #expect(RewardRequirementParser.code(in: "Pathfinder Bounty #19: The Road").isEmpty == false)
        #expect(RewardRequirementParser.code(in: "PFS(2ed) 1-06: Lost on the Spirit Road") == "1-06")
    }
}
