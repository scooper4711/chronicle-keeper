import Foundation
import Testing
@testable import CharacterKeeperKit

struct ProgressCalculatorTests {
    private let pathfinder = ProgressCalculator(campaign: .pathfinder2)
    private let starfinder = ProgressCalculator(campaign: .starfinder2)

    @Test func fullReputationMeansNormalTrack() {
        let progress = pathfinder.progress(of: SessionFactory.session(reputation: 4), settings: CharacterSettings())
        #expect(progress.track == .normal)
        #expect(progress.trackSource == .inferred)
        #expect(progress.xp == 4)
        #expect(progress.xpSource == .rules)
    }

    @Test func halfReputationMeansSlowTrack() {
        let progress = pathfinder.progress(of: SessionFactory.session(reputation: 2), settings: CharacterSettings())
        #expect(progress.track == .slow)
        #expect(progress.xp == 2)
    }

    @Test func bonusReputationIsStillNormal() {
        let progress = pathfinder.progress(of: SessionFactory.session(reputation: 6), settings: CharacterSettings())
        #expect(progress.track == .normal)
    }

    @Test func slowBountyEarnsHalfAnXP() {
        let bounty = SessionFactory.session(
            title: "Pathfinder Bounty #19", summary: "A Pathfinder Bounty designed for 1st-level characters",
            reputation: 0.5
        )
        #expect(pathfinder.progress(of: bounty, settings: CharacterSettings()).xp == 0.5)
    }

    @Test func ambiguousReputationFallsBackToTheCharacterDefault() {
        let session = SessionFactory.session(reputation: 3)
        let progress = pathfinder.progress(of: session, settings: CharacterSettings(defaultTrack: .slow))
        #expect(progress.track == .slow)
        #expect(progress.trackSource == .characterDefault)
    }

    @Test func overrideWins() {
        let session = SessionFactory.session(reputation: 4)
        let settings = CharacterSettings(overrides: [session.id: SessionOverride(track: .slow)])
        let progress = pathfinder.progress(of: session, settings: settings)
        #expect(progress.track == .slow)
        #expect(progress.trackSource == .override)
    }

    @Test func xpOverrideWins() {
        let session = SessionFactory.session()
        let settings = CharacterSettings(overrides: [session.id: SessionOverride(xp: 3)])
        let progress = pathfinder.progress(of: session, settings: settings)
        #expect(progress.xp == 3)
        #expect(progress.xpSource == .override)
    }

    @Test func starfinderBeforeSlowTrackIsAlwaysNormal() {
        let session = starfinderSession(on: "2026-04-25T08:00:00Z")
        let progress = starfinder.progress(of: session, settings: CharacterSettings(defaultTrack: .slow))
        #expect(progress.track == .normal)
        #expect(progress.trackSource == .campaignRule)
    }

    @Test func starfinderAfterSlowTrackUsesTheDefault() {
        let session = starfinderSession(on: "2026-10-03T08:00:00Z")
        let progress = starfinder.progress(of: session, settings: CharacterSettings(defaultTrack: .slow))
        #expect(progress.track == .slow)
        #expect(progress.trackSource == .characterDefault)
        #expect(progress.xp == 2)
    }

    @Test func everyStarfinderSecondEditionAdventureIsFourXP() {
        let freeRPGDay = SessionFactory.session(
            title: "Starfinder Free RPG Day", summary: "Launch into Second Edition!",
            points: SessionPoints(achievementPoints: 2, gmCredits: 0, campaign: .starfinder2), reputation: nil
        )
        let progress = starfinder.progress(of: freeRPGDay, settings: CharacterSettings())
        #expect(progress.xp == 4)
        #expect(progress.xpSource == .rules)
    }

    @Test(arguments: [(6.0, false, 4.0), (12, true, 4), (8, false, 4), (24, false, 12), (2, false, 2), (0.0, false, 0)])
    func estimatesXPFromAchievementPoints(acp: Double, isGameMaster: Bool, xp: Double) {
        let points = SessionPoints(achievementPoints: acp, gmCredits: 0, campaign: .pathfinder2)
        #expect(pathfinder.estimatedXP(from: points, isGameMaster: isGameMaster) == xp)
    }

    @Test func unknownKindsUseTheEstimate() {
        let session = SessionFactory.session(
            title: "Pathfinder Beginner Box", summary: "Take the first step",
            points: SessionPoints(achievementPoints: 12, gmCredits: 1, campaign: .pathfinder2)
        )
        let progress = pathfinder.progress(of: session, settings: CharacterSettings())
        #expect(progress.xpSource == .estimated)
        #expect(progress.xp == 4)
    }

    @Test(arguments: [(0.0, 1, 0.0), (11.5, 1, 11.5), (12, 2, 0), (30, 3, 6), (1000, 20, 772)])
    func levels(xp: Double, level: Int, intoLevel: Double) {
        let result = pathfinder.level(forXP: xp)
        #expect(result.level == level)
        #expect(result.xpIntoLevel == intoLevel)
    }

    @Test func firstEditionLevelsEveryThreeXP() {
        #expect(ProgressCalculator(campaign: .pathfinder1).level(forXP: 7).level == 3)
    }

    private func starfinderSession(on stamp: String) -> PlayedSession {
        SessionFactory.session(
            title: "Starfinder Society Scenario #1-05",
            summary: "A Starfinder Society Scenario designed for 1st- through 2nd-level characters",
            points: SessionPoints(achievementPoints: 6, gmCredits: 0, campaign: .starfinder2),
            reputation: nil, date: ISO8601DateFormatter().date(from: stamp)
        )
    }
}

struct CharacterSettingsTests {
    @Test(arguments: [
        ("https://pathbuilder2e.com/launch.html?build=123", true),
        ("  https://app.demiplane.com/nexus/pathfinder2e/character-sheet/abc ", true),
        ("file:///Users/someone/sheet.pdf", true),
        ("javascript:alert(1)", false),
        ("", false)
    ])
    func characterSheetURL(link: String, isOpenable: Bool) {
        var settings = CharacterSettings()
        settings.characterSheetLink = link
        #expect((settings.characterSheetURL != nil) == isOpenable)
    }

    @Test func decodesWithAllFields() throws {
        var settings = CharacterSettings(defaultTrack: .slow, xpAdjustment: 2)
        settings.portraitFileName = "123456-2001.png"
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(CharacterSettings.self, from: data) == settings)
    }
}
