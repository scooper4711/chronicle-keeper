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

/// The level a character was when they played each session.
struct LevelWhenPlayedTests {
    private let pathfinder = ProgressCalculator(campaign: .pathfinder2)

    @Test func eachSessionCountsTheXPOfTheOnesBefore() {
        let history = pathfinder.history(of: scenarios(reputations: [4, 4, 4, 4]), settings: CharacterSettings())
        #expect(history.map(\.session.sessionNumber) == [4, 3, 2, 1])
        #expect(history.map(\.levelWhenPlayed) == [2, 1, 1, 1])
    }

    @Test func slowTrackSessionsLevelMoreSlowly() {
        let history = pathfinder.history(
            of: scenarios(reputations: [2, 2, 2, 2, 2, 2, 4]), settings: CharacterSettings())
        #expect(history.map(\.levelWhenPlayed) == [2, 1, 1, 1, 1, 1, 1])
    }

    @Test func aTrackOverrideMovesTheLaterLevels() {
        let sessions = scenarios(reputations: [4, 4, 4, 4])
        var settings = CharacterSettings()
        settings.overrides[sessions[0].id] = SessionOverride(track: .slow)
        let history = pathfinder.history(of: sessions, settings: settings)
        #expect(history.map(\.levelWhenPlayed) == [1, 1, 1, 1])
    }

    @Test func theStartingLevelCountsFromTheFirstSession() {
        let history = pathfinder.history(
            of: scenarios(reputations: [4, 4, 4, 4]), settings: CharacterSettings(startingLevel: 3))
        #expect(history.map(\.levelWhenPlayed) == [4, 3, 3, 3])
    }

    /// "Regardless of their starting level, characters begin play with 0 XP."
    @Test(arguments: [(1, 1), (3, 3), (5, 5), (7, 7), (4, 1), (9, 1)])
    func secondEditionStartingLevels(chosen: Int, level: Int) {
        let result = ProgressCalculator(campaign: .starfinder2).level(forXP: 0, startingLevel: chosen)
        #expect(result.level == level)
        #expect(result.xp == 0 && result.xpIntoLevel == 0)
    }

    @Test func xpCountsFromTheStartingLevel() {
        let result = pathfinder.level(forXP: 30, startingLevel: 5)
        #expect(result.level == 7)
        #expect(result.xp == 30)
        #expect(result.xpIntoLevel == 6)
    }

    @Test func theStartingLevelStopsAtTheMaximum() {
        #expect(pathfinder.level(forXP: 1_000, startingLevel: 7).level == 20)
    }

    @Test func aSessionWithoutADateCountsAsTheOldest() {
        var sessions = scenarios(reputations: [4, 4, 4])
        sessions.append(SessionFactory.session(date: nil, sessionNumber: 9))
        let history = pathfinder.history(of: sessions, settings: CharacterSettings())
        #expect(history.map(\.session.sessionNumber) == [3, 2, 1, 9])
        #expect(history.map(\.levelWhenPlayed) == [2, 1, 1, 1])
    }

    @Test func sessionsOnOneDayKeepTheSitesNewestFirstOrder() {
        let day = Date(timeIntervalSince1970: 1_780_000_000)
        let sessions = [3, 2, 1].map { SessionFactory.session(date: day, sessionNumber: $0) }
        let history = pathfinder.history(of: sessions, settings: CharacterSettings())
        #expect(history.map(\.session.sessionNumber) == [3, 2, 1])
        #expect(history.map(\.levelWhenPlayed) == [1, 1, 1])
    }

    @Test func creditAppliedAwayFromTheAdventuresLevelRangeIsFlagged() {
        let inRange = scenarios(reputations: [4, 4, 4, 4])
        let heldChronicle = SessionFactory.session(
            title: "#6-04: A High-Level Scenario", summary: "A Pathfinder Society Scenario designed for "
                + "7th- through 10th-level characters",
            reputation: 4, date: Date(timeIntervalSince1970: 1_780_000_000 + 5 * 86_400), sessionNumber: 5)
        let history = pathfinder.history(of: inRange + [heldChronicle], settings: CharacterSettings())
        #expect(history.first?.session.sessionNumber == 5)
        #expect(history.first?.isOutOfLevelRange == true)
        // Below the range: credited at its lowest level, as if held until the character caught up to it.
        #expect(history.first?.creditLevel == 7)
        #expect(history.dropFirst().allSatisfy { !$0.isOutOfLevelRange })
    }

    /// Drul Goodboy GM'd (and played) "Symposium on a Fallen God" (3rd- through 6th-level) while level 1 or 2:
    /// both show credited at level 3, the range's own lowest level.
    @Test func creditBelowTwoDifferentAdventuresBothClampToTheirOwnLowestLevel() {
        let lowScenario = SessionFactory.session(
            title: "#5-12: Mischief in the Maze",
            summary: "A Pathfinder Society Scenario designed for 1st- through 4th-level characters",
            date: Date(timeIntervalSince1970: 1_780_000_000))
        let highScenario = SessionFactory.session(
            title: "#6-18: Symposium on a Fallen God",
            summary: "A Pathfinder Society Scenario designed for 3rd- through 6th-level characters",
            date: Date(timeIntervalSince1970: 1_780_000_000 + 86_400), sessionNumber: 2)
        let history = pathfinder.history(of: [lowScenario, highScenario], settings: CharacterSettings())
        #expect(history.map(\.levelWhenPlayed) == [1, 1])
        #expect(history.map(\.creditLevel) == [3, 1])
        #expect(history.map(\.isOutOfLevelRange) == [true, false])
    }

    /// Only a *held* Chronicle (played below the adventure's own range) can lose XP: a big enough award can carry
    /// it past the adventure's own highest level in one step, and the Guide's "a character's level cannot exceed
    /// the level of any Chronicle applied to them" means the rest is lost. A session played in or above its own
    /// range is never capped: "Normally, Chronicles are applied as soon as they are issued", in full.
    @Test func aHeldChronicleCanStillLoseXPThatWouldPassItsOwnHighestLevel() throws {
        let held = SessionFactory.session(
            title: "#6-04: A Mid-Tier Scenario",
            summary: "A Pathfinder Society Scenario designed for 3rd- through 4th-level characters")
        var settings = CharacterSettings()
        settings.overrides[held.id] = SessionOverride(xp: 50)
        let history = pathfinder.history(of: [held], settings: settings)
        let progress = try #require(history.first)
        #expect(progress.isOutOfLevelRange)
        #expect(progress.creditLevel == 3)
        #expect(progress.xp == 50)
        #expect(progress.xpLost > 1.9 && progress.xpLost < 2.1)
        // The level a second, ordinary session would see stops at the held Chronicle's own highest level (4).
        let next = SessionFactory.session(
            title: "#6-05: Another Scenario", date: Date(timeIntervalSince1970: 1_780_086_400))
        let withNext = pathfinder.history(of: [held, next], settings: settings)
        #expect(withNext.first?.levelWhenPlayed == 4)
    }

    /// Playing (or GMing) above an adventure's own range is ordinary, not a held Chronicle: no cap applies, so a
    /// character well above an early scenario's range still banks its full XP, the way repeated low-tier play
    /// (Starfinder Society's own scenarios, for instance) keeps leveling a character past that scenario's range.
    @Test func playingAboveAnAdventuresRangeIsNeverCapped() throws {
        let early = SessionFactory.session(
            title: "#1-01: An Early Scenario",
            summary: "A Pathfinder Society Scenario designed for 1st- through 2nd-level characters")
        var settings = CharacterSettings()
        settings.overrides[early.id] = SessionOverride(xp: 30)
        let history = pathfinder.history(of: [early], settings: settings)
        let progress = try #require(history.first)
        #expect(!progress.isOutOfLevelRange)
        #expect(progress.xpLost == 0)
        #expect(progress.xp == 30)
    }

    /// Scenarios a day apart, oldest first, numbered from 1; slow track allowed (Pathfinder).
    private func scenarios(reputations: [Double]) -> [PlayedSession] {
        reputations.enumerated().map { index, reputation in
            SessionFactory.session(
                reputation: reputation, date: Date(timeIntervalSince1970: 1_780_000_000 + Double(index) * 86_400),
                sessionNumber: index + 1)
        }
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
        var settings = CharacterSettings(defaultTrack: .slow, startingLevel: 5)
        settings.portraitFileName = "123456-2001.png"
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(CharacterSettings.self, from: data) == settings)
    }
}
