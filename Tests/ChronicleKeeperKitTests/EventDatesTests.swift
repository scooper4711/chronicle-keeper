import Foundation
import Testing
@testable import ChronicleKeeperKit

struct EventDatesTests {
    private let firstDay = Date(timeIntervalSince1970: 1_727_000_000)
    private var lastDay: Date { firstDay.addingTimeInterval(2 * 86_400) }

    private func session(_ number: Int, event: String = "con", on date: Date?) -> PlayedSession {
        SessionFactory.session(date: date, sessionNumber: number, eventCode: event)
    }

    /// The session numbers, newest first, of a history worked out with the sessions' own event dates.
    private func historyOrder(of sessions: [PlayedSession]) -> [Int] {
        let calculator = ProgressCalculator(campaign: .pathfinder2, eventDates: EventDates(sessions: sessions))
        return calculator.history(of: sessions, settings: CharacterSettings()).map(\.session.sessionNumber)
    }

    @Test func anUndatedSessionGetsItsEventsLastDay() {
        let sessions = [session(1, on: firstDay), session(2, on: lastDay), session(3, on: nil)]
        let dates = EventDates(sessions: sessions)
        #expect(dates.date(of: sessions[2]) == SessionDate(day: lastDay, isInferred: true))
        #expect(dates.date(of: sessions[0]) == SessionDate(day: firstDay))
        #expect(dates.date(of: sessions[1]) == SessionDate(day: lastDay))
    }

    @Test func anEventWithNoDatedSessionStaysUndated() {
        let sessions = [session(1, event: "other", on: lastDay), session(2, on: nil)]
        #expect(EventDates(sessions: sessions).date(of: sessions[1]) == SessionDate(day: nil))
    }

    @Test func anEventCodeUsedForLongerThanAConventionDatesNothing() {
        let muchLater = firstDay.addingTimeInterval(EventDates.longestConvention + 86_400)
        let sessions = [session(1, event: "store", on: firstDay), session(2, event: "store", on: muchLater),
                        session(3, event: "store", on: nil)]
        #expect(EventDates(sessions: sessions).date(of: sessions[2]) == SessionDate(day: nil))
    }

    @Test func anEventAsLongAsAConventionStillDatesItsSessions() {
        let finalDay = firstDay.addingTimeInterval(EventDates.longestConvention)
        let sessions = [session(1, on: firstDay), session(2, on: finalDay), session(3, on: nil)]
        #expect(EventDates(sessions: sessions).date(of: sessions[2]) == SessionDate(day: finalDay, isInferred: true))
    }

    @Test func sessionsWithoutAnEventCodeShareNoEvent() {
        let sessions = [session(1, event: "", on: lastDay), session(2, event: "", on: nil)]
        #expect(EventDates(sessions: sessions).date(of: sessions[1]) == SessionDate(day: nil))
    }

    @Test func withoutEventDatesASessionKeepsPaizosDate() {
        #expect(EventDates().date(of: session(1, on: nil)) == SessionDate(day: nil))
        #expect(EventDates().date(of: session(1, on: lastDay)) == SessionDate(day: lastDay))
    }

    @Test func theRosterDatesASessionFromAnotherCharactersSessionAtTheEvent() throws {
        var other = PlayedSessionFields()
        other.date = lastDay
        other.eventCode = "con"
        other.sessionNumber = 9
        other.playerNumber = "123456-2009"
        other.characterName = "Someone Else"
        other.points = SessionPoints(achievementPoints: 4, gmCredits: 0, campaign: .pathfinder2)
        let summary = CharacterSummary(
            number: "123456-2001", campaign: .pathfinder2, name: "Valeria Stonebrook", factions: [], standing: [])
        let roster = CharacterRoster(
            summaries: [summary], sessions: [session(1, on: nil), PlayedSession(fields: other)])
        let played = try #require(roster.characters.first?.sessions.first)
        #expect(played.date == SessionDate(day: lastDay, isInferred: true))
        // The session itself stays what paizo.com said, so a saved copy never passes the guess off as the site's.
        #expect(played.session.date == nil)
    }

    @Test func anInferredDateComesAfterTheSessionsReallyPlayedThatDay() {
        // The site lists newest first. Listed after the dated session, the undated one would count as played
        // before it; listed before, after it. Either way its Chronicle applies when the convention ends.
        #expect(historyOrder(of: [session(2, on: lastDay), session(1, on: nil)]) == [1, 2])
        #expect(historyOrder(of: [session(1, on: nil), session(2, on: lastDay)]) == [1, 2])
    }

    @Test func anInferredDateDecidesWhetherSlowTrackWasAllowed() throws {
        let beforeSlowTrack = try #require(ISO8601DateFormatter().date(from: "2026-04-25T08:00:00Z"))
        let points = SessionPoints(achievementPoints: 4, gmCredits: 0, campaign: .starfinder2)
        let sessions = [
            SessionFactory.session(points: points, date: beforeSlowTrack, sessionNumber: 1, eventCode: "con"),
            SessionFactory.session(points: points, reputation: nil, date: nil, sessionNumber: 2, eventCode: "con")
        ]
        let calculator = ProgressCalculator(campaign: .starfinder2, eventDates: EventDates(sessions: sessions))
        let progress = calculator.progress(of: sessions[1], settings: CharacterSettings(defaultTrack: .slow))
        #expect(progress.track == .normal)
        #expect(progress.trackSource == .campaignRule)
    }
}
