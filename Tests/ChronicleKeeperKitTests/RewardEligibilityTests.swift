import Foundation
import Testing
@testable import ChronicleKeeperKit

/// Characters and boons for the reward tests.
enum RewardFactory {
    /// A character with one session per title, checked against the real lists.
    static func record(
        campaign: Campaign = .pathfinder2, factions: [NamedValue] = [], playing titles: [String] = []
    ) -> CharacterRecord {
        let summary = CharacterSummary(
            number: "123456-2001", campaign: campaign, name: "Valeria Stonebrook", factions: factions, standing: [])
        let points = SessionPoints(achievementPoints: 4, gmCredits: 0, campaign: campaign)
        let sessions = titles.enumerated().map { index, title in
            SessionFactory.session(title: title, points: points, sessionNumber: index + 1)
        }
        return CharacterRoster(summaries: [summary], sessions: sessions).characters[0]
    }

    static func boon(_ name: String, character: String = "Valeria Stonebrook") -> Boon {
        var fields = BoonFields()
        fields.characterName = character
        fields.name = name
        return Boon(fields: fields)
    }

    static func eligibility() throws -> RewardEligibility {
        RewardEligibility(catalog: RewardCatalog(offers: try RewardConditions.offers(), fetchedAt: Date()))
    }

    /// The names of what the character may claim.
    static func claims(_ record: CharacterRecord, owning owned: [String] = []) throws -> [String] {
        try eligibility().claimable(for: record, owned: owned.map { boon($0) }).map(\.title)
    }
}

@Suite("Reward eligibility")
struct RewardEligibilityTests {
    private let doctor = "PFS (2ed) Scenario #6-03: Is There a Doctor in the House?"

    @Test("A character who played the adventure may claim its boon, and the session is named")
    func playingEarnsTheBoon() throws {
        let record = RewardFactory.record(playing: ["#6-03: Godsrain in a Godless Land"])
        let claims = try RewardFactory.eligibility().claimable(for: record, owned: [])
        let claim = try #require(claims.first)
        #expect(claims.count == 1)
        #expect(claim.title == doctor)
        #expect(claim.reason == "You played #6-03: Godsrain in a Godless Land")
        #expect(claim.sessionIDs == [record.sessions[0].id])
        #expect(claim.faction.isEmpty)
        #expect(!claim.isChoice)
    }

    @Test("A boon the character has is not offered again, however its dashes and capitals are written")
    func anOwnedBoonIsNotOffered() throws {
        let record = RewardFactory.record(playing: ["#6-03: Godsrain in a Godless Land", "#1-05: Trailblazer's Bounty"])
        // Two sessions also earn the Wayfinder, which the character has too.
        let owned = ["pfs (2ed) scenario #6–03:  Is there a Doctor in the House?", "Wayfinder"]
        #expect(try RewardFactory.claims(record, owning: owned) == ["PFS (2ed) Scenario #1-05: Trailblazer’s Bounty"])
    }

    @Test("A character with no sessions and no reputation may claim nothing")
    func nothingWithoutSessions() throws {
        #expect(try RewardFactory.claims(RewardFactory.record()).isEmpty)
    }

    @Test("An adventure's lettered boons are one choice")
    func letteredBoonsAreOneChoice() throws {
        let record = RewardFactory.record(playing: ["#1-04: Bandits of Immenwood"])
        let claims = try RewardFactory.eligibility().claimable(for: record, owned: [])
        let claim = try #require(claims.first)
        #expect(claims.count == 1)
        #expect(claim.isChoice)
        #expect(claim.offers.map(\.name) == [
            "PFS (2ed) Scenario #1–04: Bandits of Immenwood Boon A",
            "PFS (2ed) Scenario #1-04: Bandits of Immenwood Boon B"
        ])
        #expect(claim.title == "PFS (2ed) Scenario #1-04: Bandits of Immenwood: Boon A or Boon B")
    }

    @Test("Having one of an adventure's lettered boons rules out the others", arguments: [
        "PFS (2ed) Scenario #1–04: Bandits of Immenwood Boon A", "PFS (2ed) Scenario #1-04: Bandits of Immenwood Boon B"
    ])
    func oneLetteredBoonRulesOutTheOthers(owned: String) throws {
        let record = RewardFactory.record(playing: ["#1-04: Bandits of Immenwood"])
        #expect(try RewardFactory.claims(record, owning: [owned]).isEmpty)
    }

    @Test("Boons of one adventure that aren't lettered are each offered")
    func unletteredBoonsStaySeparate() throws {
        let title = "Pathfinder Adventure Path #187: The Seventh Arch (Gatewalkers 1 of 3)"
        let record = RewardFactory.record(playing: [title])
        let stargazer = "Gatewalkers: The Seventh Arch – Stargazer"
        #expect(try RewardFactory.claims(record) == ["Gatewalkers: The Seventh Arch – On the Bubble", stargazer])
        let bubble = ["Gatewalkers: The Seventh Arch – On the Bubble"]
        #expect(try RewardFactory.claims(record, owning: [stargazer]) == bubble)
    }

    @Test("A volume earns its series' \"at least one\" boon along with its own")
    func aVolumeEarnsItsSeriesBoon() throws {
        let title = "Pathfinder Adventure Path #169: Kindled Magic (Strength of Thousands 1 of 6)"
        #expect(try RewardFactory.claims(RewardFactory.record(playing: [title])) == [
            "Strength of Thousands - Magaambyan Attendant", "Strength of Thousands: Kindled Magic - Study Group",
            "Strength of Thousands: Kindled Magic - Expanded Summoning"
        ])
    }

    @Test("The name's number decides, not a title that happens to match")
    func aDifferentNumberIsADifferentAdventure() throws {
        #expect(try RewardFactory.claims(RewardFactory.record(playing: ["#9-98: Twice in Steel"])).isEmpty)
        let record = RewardFactory.record(playing: ["#6-14: Twice in Steel"])
        #expect(try RewardFactory.claims(record) == ["PFS (2ed) Scenario #6-14: Alicorn's Blessing"])
    }

    @Test("A short title has to match whole")
    func aShortTitleMatchesWhole() throws {
        #expect(try RewardFactory.claims(RewardFactory.record(playing: ["Adventure: Stage Fright Night"])).isEmpty)
        let volume = "Pathfinder Adventure Path #204: Stage Fright (Curtain Call 1 of 3)"
        let record = RewardFactory.record(playing: [volume])
        #expect(try RewardFactory.claims(record).count == 2)
    }

    @Test("A session run as Game Master counts as played")
    func gameMasterCreditCounts() throws {
        let summary = CharacterSummary(
            number: "123456-2001", campaign: .pathfinder2, name: "Valeria Stonebrook", factions: [], standing: [])
        let session = SessionFactory.session(
            title: "#6-03: Godsrain in a Godless Land",
            points: SessionPoints(achievementPoints: 0, gmCredits: 4, campaign: .pathfinder2))
        let record = CharacterRoster(summaries: [summary], sessions: [session]).characters[0]
        #expect(try RewardFactory.claims(record) == [doctor])
    }

    @Test("Reputation earns the faction's rewards and the any-faction ones, up to the status reached")
    func reputationEarnsRewards() throws {
        let factions = [NamedValue(name: "Envoy's Alliance", value: 14), NamedValue(name: "Horizon Hunters", value: 22)]
        let claims = try RewardFactory.eligibility().claimable(for: RewardFactory.record(factions: factions), owned: [])
        #expect(claims.map(\.title) == ["Rugged Mentor (Horizon Hunters)", "Horizon Hunters Gear", "Expert Hireling"])
        #expect(claims.map(\.faction) == ["Horizon Hunters", "Horizon Hunters", "Horizon Hunters"])
        #expect(claims[0].reason == "You have 22 reputation with Horizon Hunters; it takes 20")
        #expect(claims[0].sessionIDs.isEmpty)
    }

    @Test("An any-faction reward goes by the faction the character stands highest with")
    func anyFactionUsesTheBest() throws {
        let factions = [NamedValue(name: "Grand Archive", value: 61), NamedValue(name: "Radiant Oath", value: 130)]
        let claims = try RewardFactory.eligibility().claimable(for: RewardFactory.record(factions: factions), owned: [])
        let hireling = try #require(claims.first { $0.title == "Master Hireling" })
        #expect(hireling.faction == "Radiant Oath")
        #expect(claims.contains { $0.title == "Heroic Recall (Grand Archive)" })
    }

    @Test("The Wayfinder takes two sessions")
    func sessionsEarnTheWayfinder() throws {
        #expect(try RewardFactory.claims(RewardFactory.record(playing: ["#9-01: One"])).isEmpty)
        let record = RewardFactory.record(playing: ["#9-01: One", "#9-02: Two"])
        let claims = try RewardFactory.eligibility().claimable(for: record, owned: [])
        #expect(claims.map(\.title) == ["Wayfinder"])
        #expect(claims[0].reason == "You have played 2 sessions; it takes 2")
    }

    @Test("OR takes one of the adventures and AND takes each")
    func eitherAndEach() throws {
        let sea = RewardFactory.record(playing: ["#2-02: Mountain of Sea and Sky"])
        #expect(try RewardFactory.claims(sea) == ["Lantern Lodge Gear"])
        let part1 = "#1-16: The Perennial Crown Part 1: Opal of Bhopan"
        let part2 = "#1-17: The Perennial Crown Part 2: The Thorned Monarch"
        let half = try RewardFactory.claims(RewardFactory.record(playing: [part1]))
        #expect(!half.contains("Open Road Lodge Gear"))
        let record = RewardFactory.record(playing: [part1, part2])
        let both = try RewardFactory.eligibility().claimable(for: record, owned: [])
        let gear = try #require(both.first { $0.title == "Open Road Lodge Gear" })
        #expect(gear.reason == "You played \(part1) and \(part2)")
        #expect(gear.sessionIDs.count == 2)
    }

    @Test("Starfinder's rewards go by the Summary tab's faction names, which the lists shorten")
    func starfinderFactions() throws {
        let factions = [
            NamedValue(name: "Second Seekers (Ehu Hadif)", value: 6), NamedValue(name: "Acquisitives", value: 15),
            NamedValue(name: "Wayfinders", value: 4)
        ]
        let record = RewardFactory.record(campaign: .starfinder1, factions: factions, playing: ["#3-00: The Last Bite"])
        #expect(try RewardFactory.claims(record) == [
            "AbadarCorp Endorsement (SFS 3-00: The Last Bite)", "Purveyor of Fortunes (Acquisitives)",
            "Acquisitives Champion", "Seeker of Knowledge (Second Seekers: Ehu Hadif)"
        ])
    }

    @Test("A scenario the lists name only by title is found among numbered sessions")
    func aTitleFindsANumberedSession() throws {
        let record = RewardFactory.record(campaign: .starfinder1, playing: ["#6-10: The Death of Kortus IV"])
        #expect(try RewardFactory.claims(record) == ["Hero’s Commendation (The Death of Kortus IV)"])
    }

    @Test("Another campaign's rewards are never offered")
    func campaignsStayApart() throws {
        let record = RewardFactory.record(campaign: .starfinder2, playing: ["#3-00: The Last Bite", "#6-03: Godsrain"])
        #expect(try RewardFactory.claims(record).isEmpty)
    }

    @Test("A faction's name matches whole or as the list shortens it")
    func factionNames() {
        #expect(Claimant.isFaction("Second Seekers (Ehu Hadif)", named: "Second Seekers (Ehu)"))
        #expect(Claimant.isFaction("Acquisitives", named: "the Acquisitives"))
        #expect(!Claimant.isFaction("Second Seekers", named: "Second Seekers (Jadnura)"))
        #expect(!Claimant.isFaction("Grand Lodge", named: "Grand Archive"))
        #expect(!Claimant.isFaction("Grand Lodge", named: ""))
    }
}
