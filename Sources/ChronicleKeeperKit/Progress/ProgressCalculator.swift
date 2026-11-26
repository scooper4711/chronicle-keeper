import Foundation

/// Turns a character's sessions into XP and a level, inferring slow track where the site doesn't say.
public struct ProgressCalculator: Sendable {
    public let rules: CampaignRules
    /// Dates for the sessions paizo.com gave none, worked out from the whole account's sessions.
    public let eventDates: EventDates

    public init(campaign: Campaign, eventDates: EventDates = EventDates()) {
        rules = CampaignRules(campaign: campaign)
        self.eventDates = eventDates
    }

    public func progress(of session: PlayedSession, settings: CharacterSettings) -> SessionProgress {
        let kind = AdventureClassifier.kind(of: session.adventure)
        let override = settings.override(for: session) ?? SessionOverride()
        // The user's own correction beats the sheet, whichever of the two it sets (R2.11).
        let sheet = override == SessionOverride() ? sheetCredit(of: session, kind: kind, settings: settings) : nil
        var (track, trackSource) = track(of: session, kind: kind, override: override, settings: settings)
        if let sheetTrack = sheet?.track { (track, trackSource) = (sheetTrack, .chronicle) }
        var (xp, xpSource) = normalXP(of: session, kind: kind)
        xp *= track.rewardFactor
        if let sheet { (xp, xpSource) = (sheet.xp, .chronicle) }
        if let entered = override.xp { (xp, xpSource) = (entered, .override) }
        return SessionProgress(
            session: session, date: eventDates.date(of: session), kind: kind, track: track,
            trackSource: trackSource, xp: xp, xpSource: xpSource
        )
    }

    /// Every session, newest first, each with the level it was credited at and where that fell in the order
    /// credit was actually banked (see `CreditApplier`). Sessions without a date count as the oldest; sessions
    /// on the same day keep the site's order (newest first), except that a date inferred from the event's last day
    /// comes after the sessions really played that day, as the convention's Chronicles apply when it ends.
    public func history(of sessions: [PlayedSession], settings: CharacterSettings) -> [SessionProgress] {
        let oldestFirst = sessions.enumerated()
            .map { (offset: $0.offset, progress: progress(of: $0.element, settings: settings)) }
            .sorted { Self.isEarlier($0, than: $1) }
            .map(\.progress)
        let applier = CreditApplier(rules: rules, startingLevel: settings.startingLevel) { xp in
            self.level(forXP: xp, startingLevel: settings.startingLevel)
        }
        return applier.apply(to: oldestFirst).reversed()
    }

    /// `offset` is the session's place in the site's list, which is newest first.
    private static func isEarlier(
        _ first: (offset: Int, progress: SessionProgress), than second: (offset: Int, progress: SessionProgress)
    ) -> Bool {
        let (one, two) = (first.progress.date, second.progress.date)
        if one.day != two.day { return (one.day ?? .distantPast) < (two.day ?? .distantPast) }
        if one.isInferred != two.isInferred { return two.isInferred }
        return first.offset > second.offset
    }

    /// The level a character reaches with this much XP, counting up from the level they began play at.
    public func level(forXP xp: Double, startingLevel: Int = 1) -> CharacterLevel {
        let start = rules.startingLevel(startingLevel)
        let earned = Int((max(xp, 0) / rules.xpPerLevel).rounded(.down))
        let level = min(start + earned, rules.maximumLevel)
        let intoLevel = max(xp, 0) - Double(level - start) * rules.xpPerLevel
        return CharacterLevel(level: level, xp: xp, xpIntoLevel: intoLevel, xpPerLevel: rules.xpPerLevel)
    }

    // MARK: - Track

    func track(
        of session: PlayedSession, kind: AdventureKind, override: SessionOverride, settings: CharacterSettings
    ) -> (Track, TrackSource) {
        if let chosen = override.track { return (chosen, .override) }
        guard rules.allowsSlowTrack(on: eventDates.date(of: session).day) else { return (.normal, .campaignRule) }
        if let inferred = inferredTrack(of: session, kind: kind) { return (inferred, .inferred) }
        return (settings.defaultTrack, .characterDefault)
    }

    /// Slow track halves the reputation, so half the normal reputation means slow and the full amount
    /// (or more, with a bonus) means normal. Anything else is ambiguous.
    private func inferredTrack(of session: PlayedSession, kind: AdventureKind) -> Track? {
        guard rules.hasFactions, let earned = session.reputation,
              let normal = rules.normalReputation(for: kind), normal > 0 else { return nil }
        if earned >= normal { return .normal }
        return earned == normal / 2 ? .slow : nil
    }

    // MARK: - The chronicle sheet

    /// What a session's chronicle sheet says it gave, when that is XP the adventure can give (R2.11); nil without
    /// a sheet, without XP read from it, or when the XP read is impossible, which `SheetChecker` reports.
    func sheetCredit(of session: PlayedSession, kind: AdventureKind, settings: CharacterSettings) -> SheetCredit? {
        guard let xp = settings.wealth.sheetReadings[session.keyWithinCharacter]?.xp else { return nil }
        let allowsSlow = rules.allowsSlowTrack(on: eventDates.date(of: session).day)
        guard let normal = rules.normalXP(for: kind) else {
            // No rule for this kind: the amounts adventures give, with no way to tell the track from them.
            let amounts = Self.xpAwards + (allowsSlow ? Self.xpAwards.map { $0 / 2 } : [])
            return amounts.contains(xp) ? SheetCredit(xp: xp, track: nil) : nil
        }
        if xp == normal { return SheetCredit(xp: xp, track: .normal) }
        return allowsSlow && xp == normal / 2 ? SheetCredit(xp: xp, track: .slow) : nil
    }

    // MARK: - XP

    private func normalXP(of session: PlayedSession, kind: AdventureKind) -> (Double, XPSource) {
        if let xp = rules.normalXP(for: kind) { return (xp, .rules) }
        return (estimatedXP(from: session.points, isGameMaster: session.isGameMaster), .estimated)
    }

    /// Achievement Points are the adventure's XP times the event's multiplier (1 to 2), doubled for the GM,
    /// and slow track doesn't change them. Scenario-sized XP is tried first, being the most common.
    func estimatedXP(from points: SessionPoints, isGameMaster: Bool) -> Double {
        let base = points.achievementPoints / (isGameMaster ? 2 : 1)
        return Self.xpAwards.first { Self.eventMultipliers.contains(base / $0) } ?? 0
    }

    /// The XP an adventure can give on normal track: a scenario's, a long adventure's, a quest's and a bounty's.
    private static let xpAwards: [Double] = [4, 12, 2, 1]

    private static let eventMultipliers: Set<Double> = [1, 1.25, 1.5, 1.75, 2]
}

/// What a chronicle sheet's XP means for its session: the XP, and the track where the adventure's kind tells it.
struct SheetCredit: Hashable, Sendable {
    let xp: Double
    let track: Track?
}

/// A character's level and how far it is through it.
public struct CharacterLevel: Hashable, Sendable {
    public let level: Int
    public let xp: Double
    public let xpIntoLevel: Double
    public let xpPerLevel: Double

    public var fractionIntoLevel: Double { min(xpIntoLevel / xpPerLevel, 1) }
}
