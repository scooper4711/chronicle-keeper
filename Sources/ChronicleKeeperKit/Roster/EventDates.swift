import Foundation

/// When a session counts as played, and whether paizo.com said so.
public struct SessionDate: Hashable, Sendable {
    /// Nil when paizo.com gave no date and the session's event gives none either.
    public let day: Date?
    /// True when paizo.com gave no date and `day` is the last day of the session's convention instead.
    public let isInferred: Bool

    public init(day: Date?, isInferred: Bool = false) {
        self.day = day
        self.isInferred = isInferred
    }
}

/// paizo.com leaves the date off some sessions reported at a convention. Such a session counts as played on the
/// last date of any of the account's sessions at the same event, since Organized Play applies a convention's
/// Chronicles when it ends. A session at an event with no dated session at all stays undated.
///
/// The dates are worked out from the whole account, as another character's session can be the one that dates the
/// event, and never written to the `PlayedSession`, which stays what paizo.com said.
public struct EventDates: Sendable {
    /// A convention's sessions fall within days of each other. An event code a store or lodge reuses for years of
    /// weekly play is no convention, and its newest session says nothing about when an undated one was played.
    static let longestConvention: TimeInterval = 7 * 86_400

    private let lastDays: [String: Date]

    /// No event dates: every session keeps paizo.com's own date.
    public init() {
        lastDays = [:]
    }

    public init(sessions: [PlayedSession]) {
        var spans: [String: ClosedRange<Date>] = [:]
        // Sessions without an event code share no event.
        for session in sessions where !session.eventCode.isEmpty {
            guard let date = session.date else { continue }
            let span = spans[session.eventCode] ?? date...date
            spans[session.eventCode] = min(span.lowerBound, date)...max(span.upperBound, date)
        }
        lastDays = spans
            .filter { $0.value.upperBound.timeIntervalSince($0.value.lowerBound) <= Self.longestConvention }
            .mapValues(\.upperBound)
    }

    public func date(of session: PlayedSession) -> SessionDate {
        if let date = session.date { return SessionDate(day: date) }
        guard let lastDay = lastDays[session.eventCode] else { return SessionDate(day: nil) }
        return SessionDate(day: lastDay, isInferred: true)
    }
}
