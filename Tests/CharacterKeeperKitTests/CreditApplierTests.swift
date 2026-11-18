import Foundation
import Testing
@testable import CharacterKeeperKit

/// The level a character was when they played each session, and how held Chronicles are applied once they
/// catch up to their adventure's own range (see `CreditApplier`).
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

    /// The running total through each session, including a held Chronicle's XP once it's banked.
    @Test func totalXPRunsCumulatively() {
        let history = pathfinder.history(of: scenarios(reputations: [4, 2, 4]), settings: CharacterSettings())
        #expect(history.reversed().map(\.totalXP) == [4, 6, 10])
    }

    /// Only a *held* Chronicle (played below the adventure's own range) can lose XP: a big enough award can carry
    /// it past the adventure's own highest level in one step, and the Guide's "a character's level cannot exceed
    /// the level of any Chronicle applied to them" means the rest is lost. A session played in or above its own
    /// range is never capped: "Normally, Chronicles are applied as soon as they are issued", in full.
    @Test func aHeldChronicleWithNothingToCatchItUpIsNeverApplied() throws {
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
        #expect(progress.xpLost == 50)
        #expect(progress.totalXP == 0)
    }

    /// Once an ordinary session catches the character up to a held Chronicle's range, it's applied as a batch,
    /// capped at that adventure's own highest level if its XP would otherwise carry the character past it.
    @Test func aHeldChronicleAppliedOnceCaughtUpCanStillLoseExcessXP() throws {
        let held = SessionFactory.session(
            title: "#6-04: A Mid-Tier Scenario",
            summary: "A Pathfinder Society Scenario designed for 3rd- through 4th-level characters",
            date: Date(timeIntervalSince1970: 1_780_000_000), sessionNumber: 1)
        let catchUp = SessionFactory.session(
            title: "#1-01: An Ordinary Session", date: Date(timeIntervalSince1970: 1_780_086_400), sessionNumber: 2)
        var settings = CharacterSettings()
        settings.overrides[held.id] = SessionOverride(xp: 50)
        settings.overrides[catchUp.id] = SessionOverride(xp: 24)
        let history = pathfinder.history(of: [held, catchUp], settings: settings)
        let heldResult = try #require(history.first { $0.session.id == held.id })
        let catchUpResult = try #require(history.first { $0.session.id == catchUp.id })
        #expect(catchUpResult.applyOrder == 1)
        #expect(heldResult.applyOrder == 2)
        // Caps out exactly at the held Chronicle's own highest level (4), the level it ends up at once it lands.
        #expect(heldResult.creditLevel == 4)
        #expect(heldResult.xpLost > 25.9 && heldResult.xpLost < 26.1)
        #expect(heldResult.levelWhenPlayed == 1)
        // Capped at the held Chronicle's own highest level (4), not past it.
        #expect(catchUpResult.totalXP + (heldResult.xp - heldResult.xpLost) < 48)
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

/// Drul Goodboy's real sessions (see tmp/drul-sessions.csv): two scenarios played below their own range
/// ("Demonic Afterparty" and "Symposium on a Fallen God") are held until he catches up to level 3, then applied
/// as a batch, in the order played, right after the session that first reaches that level.
struct DrulGoodboyRegressionTests {
    private let pathfinder = ProgressCalculator(campaign: .pathfinder2)

    @Test func drulsHeldSessionsApplyOnceHeCatchesUpToLevelThree() throws {
        let sessions = Self.drulsSessions()
        let history = pathfinder.history(of: sessions, settings: CharacterSettings())

        let byApplyOrder = history.sorted { $0.applyOrder < $1.applyOrder }
        #expect(byApplyOrder.map(\.session.adventure.title) == [
            "#5-12: Mischief in the Maze", "#6-13: All That Glitters",
            "Intro to the Year of Battle’s Spark—Enough is Enough (Sep 20)",
            "Intro to the Year of Battle’s Spark—Enough is Enough (Sep 30)",
            "#7-02: Shipyard Sabotage", "#5-07: Sewer Dragon Crisis", "Quest #4: Port Peril Pub Crawl",
            "Pathfinder Quest (Series 2) #19: The Elsewhere Feast", "#5-19: Demonic Afterparty",
            "#6-18: Symposium on a Fallen God", "Pathfinder Quest (Series 2) #21: Infernal Infiltration",
            "#7-06: Brastlewark at War Part 1: The Gnome Defection"
        ])
        #expect(byApplyOrder.map(\.creditLevel) == [1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4])
        let progress = byApplyOrder.map { $0.totalXP.truncatingRemainder(dividingBy: 12) }
        #expect(progress == [4, 6, 10, 2, 6, 10, 11, 1, 5, 9, 11, 3])
        #expect(byApplyOrder.allSatisfy { $0.xpLost == 0 })

        let demonicAfterparty = try #require(history.first(withTitle: "#5-19: Demonic Afterparty"))
        let symposium = try #require(history.first(withTitle: "#6-18: Symposium on a Fallen God"))
        #expect(demonicAfterparty.isOutOfLevelRange && demonicAfterparty.creditLevel == 3)
        #expect(symposium.isOutOfLevelRange && symposium.creditLevel == 3)
        // Nothing is actually lost in Drul's real numbers: both held sessions still fit their own 3-6 range.
        #expect(history.reduce(0.0) { $0 + $1.xp - $1.xpLost } == 39)
        #expect(pathfinder.level(forXP: 39, startingLevel: 1).level == 4)
    }

    /// Dates and titles from tmp/drul-sessions.csv (a real account, kept out of the repository).
    private static func drulsSessions() -> [PlayedSession] {
        firstHalfOfDrulsSessions() + secondHalfOfDrulsSessions()
    }

    private static func firstHalfOfDrulsSessions() -> [PlayedSession] {
        [
            SessionFactory.session(
                title: "#5-12: Mischief in the Maze", summary: Self.inRange, reputation: 4,
                date: Self.utcDate(year: 2025, month: 4, day: 24), sessionNumber: 1),
            SessionFactory.session(
                title: "#5-19: Demonic Afterparty", summary: Self.aboveRange, reputation: 4,
                date: Self.utcDate(year: 2025, month: 4, day: 27), sessionNumber: 2),
            SessionFactory.session(
                title: "#6-13: All That Glitters", summary: Self.inRange, reputation: 2,
                date: Self.utcDate(year: 2025, month: 7, day: 1), sessionNumber: 3),
            SessionFactory.session(
                title: "#6-18: Symposium on a Fallen God", summary: Self.aboveRange, reputation: 4,
                date: Self.utcDate(year: 2025, month: 9, day: 20), sessionNumber: 4),
            SessionFactory.session(
                title: "Intro to the Year of Battle’s Spark—Enough is Enough (Sep 20)", summary: Self.inRange,
                reputation: 4, date: Self.utcDate(year: 2025, month: 9, day: 20), sessionNumber: 5),
            SessionFactory.session(
                title: "Intro to the Year of Battle’s Spark—Enough is Enough (Sep 30)", summary: Self.inRange,
                reputation: 4, date: Self.utcDate(year: 2025, month: 9, day: 30), sessionNumber: 6)
        ]
    }

    private static func secondHalfOfDrulsSessions() -> [PlayedSession] {
        [
            SessionFactory.session(
                title: "#7-02: Shipyard Sabotage", summary: Self.inRange, reputation: 4,
                date: Self.utcDate(year: 2025, month: 10, day: 14), sessionNumber: 7),
            SessionFactory.session(
                title: "#5-07: Sewer Dragon Crisis", summary: Self.inRange, reputation: 4,
                date: Self.utcDate(year: 2025, month: 11, day: 18), sessionNumber: 8),
            SessionFactory.session(
                title: "Quest #4: Port Peril Pub Crawl", summary: Self.quest1, reputation: 1,
                date: Self.utcDate(year: 2025, month: 12, day: 2), sessionNumber: 9),
            SessionFactory.session(
                title: "Pathfinder Quest (Series 2) #19: The Elsewhere Feast", summary: Self.quest2,
                reputation: 2, date: Self.utcDate(year: 2025, month: 12, day: 16), sessionNumber: 10),
            SessionFactory.session(
                title: "Pathfinder Quest (Series 2) #21: Infernal Infiltration", summary: Self.quest2,
                reputation: 2, date: Self.utcDate(year: 2026, month: 1, day: 13), sessionNumber: 11),
            SessionFactory.session(
                title: "#7-06: Brastlewark at War Part 1: The Gnome Defection", summary: Self.inRange,
                reputation: 4, date: Self.utcDate(year: 2026, month: 4, day: 24), sessionNumber: 12)
        ]
    }

    private static let inRange = "A Pathfinder Society Scenario designed for 1st- through 4th-level characters"
    private static let aboveRange = "A Pathfinder Society Scenario designed for 3rd- through 6th-level characters"
    private static let quest1 = "A Pathfinder Society Quest designed for levels 1–4 (subtiers 1–2 and 3–4)"
    private static let quest2 = "A Pathfinder Society Quest designed for 1st- through 4th-level characters"

    private static func utcDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents(year: year, month: month, day: day)
        components.timeZone = TimeZone(identifier: "UTC")
        // swiftlint:disable:next force_unwrapping
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}

extension [SessionProgress] {
    fileprivate func first(withTitle title: String) -> SessionProgress? {
        first { $0.session.adventure.title == title }
    }
}
