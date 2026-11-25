import Testing
@testable import ChronicleKeeperKit

@Suite("Reputation ladder")
struct ReputationLadderTests {
    private let pathfinder = CampaignRules(campaign: .pathfinder2).reputationLadder
    private let starfinder = CampaignRules(campaign: .starfinder1).reputationLadder

    @Test("Pathfinder Society (second edition) statuses begin at 0, 20, 60 and 120", arguments: [
        (0, "Ignored"), (19, "Ignored"), (20, "Liked"), (59, "Liked"),
        (60, "Admired"), (119, "Admired"), (120, "Revered"), (400, "Revered")
    ])
    func pathfinderStatus(reputation: Int, status: String) {
        #expect(pathfinder.status(for: reputation) == status)
    }

    @Test("Starfinder Society (first edition) tiers begin at 0, 5, 15, 25 and 45", arguments: [
        (0, "Tier 0"), (4, "Tier 0"), (5, "Tier 1"), (14, "Tier 1"), (15, "Tier 2"),
        (24, "Tier 2"), (25, "Tier 3"), (44, "Tier 3"), (45, "Tier 4"), (90, "Tier 4")
    ])
    func starfinderTier(reputation: Int, tier: String) {
        #expect(starfinder.status(for: reputation) == tier)
    }

    @Test("The distance to the next status counts up to its threshold")
    func distanceToNextStatus() {
        #expect(pathfinder.distanceToNextStatus(from: 8) == "12 more to Liked")
        #expect(pathfinder.distanceToNextStatus(from: 68) == "52 more to Revered")
        #expect(starfinder.distanceToNextStatus(from: 14) == "1 more to Tier 2")
    }

    @Test("The top of the ladder has no next status")
    func topHasNoNextStatus() {
        #expect(pathfinder.nextStep(after: 120) == nil)
        #expect(pathfinder.distanceToNextStatus(from: 120).isEmpty)
        #expect(starfinder.distanceToNextStatus(from: 45).isEmpty)
    }

    @Test("A status's threshold is found whatever its capitals")
    func thresholdOfStatus() {
        #expect(pathfinder.threshold(of: "Liked") == 20)
        #expect(pathfinder.threshold(of: "admired") == 60)
        #expect(pathfinder.threshold(of: "Revered") == 120)
        #expect(pathfinder.threshold(of: "Tier 1") == nil)
        #expect(starfinder.threshold(of: "Tier 1") == 5)
    }

    @Test("Campaigns without statuses have an empty ladder", arguments: [
        Campaign.pathfinder1, .starfinder2, .other("PFS Playtest")
    ])
    func campaignsWithoutStatuses(campaign: Campaign) {
        let ladder = CampaignRules(campaign: campaign).reputationLadder
        #expect(ladder.isEmpty)
        #expect(ladder.status(for: 30).isEmpty)
        #expect(ladder.distanceToNextStatus(from: 30).isEmpty)
        #expect(ladder.threshold(of: "Liked") == nil)
    }

    @Test("Reputation below the lowest status has none")
    func negativeReputation() {
        #expect(pathfinder.status(for: -1).isEmpty)
        #expect(pathfinder.distanceToNextStatus(from: -1) == "1 more to Ignored")
    }

    @Test("Steps given out of order are put lowest first")
    func stepsAreSorted() {
        let ladder = ReputationLadder(steps: [.init(name: "High", threshold: 10), .init(name: "Low", threshold: 0)])
        #expect(ladder.steps.map(\.name) == ["Low", "High"])
        #expect(ladder.status(for: 3) == "Low")
    }
}
