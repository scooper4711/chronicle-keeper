import Foundation

/// Turns a character's sessions into XP and a level, inferring slow track where the site doesn't say.
public struct ProgressCalculator: Sendable {
    public let rules: CampaignRules

    public init(campaign: Campaign) {
        rules = CampaignRules(campaign: campaign)
    }

    public func progress(of session: PlayedSession, settings: CharacterSettings) -> SessionProgress {
        let kind = AdventureClassifier.kind(of: session.adventure)
        let override = settings.overrides[session.id] ?? SessionOverride()
        let (track, trackSource) = track(of: session, kind: kind, override: override, settings: settings)
        let (normalXP, xpSource) = normalXP(of: session, kind: kind)
        let xp = override.xp ?? normalXP * track.rewardFactor
        return SessionProgress(
            session: session, kind: kind, track: track, trackSource: trackSource,
            xp: xp, xpSource: override.xp == nil ? xpSource : .override
        )
    }

    /// Every session, newest first, each with the level the character was when it was played. Sessions without a
    /// date count as the oldest; sessions on the same day keep the site's order (newest first).
    public func history(of sessions: [PlayedSession], settings: CharacterSettings) -> [SessionProgress] {
        let oldestFirst = sessions.enumerated()
            .sorted { ($0.element.date ?? .distantPast, -$0.offset) < ($1.element.date ?? .distantPast, -$1.offset) }
            .map { progress(of: $0.element, settings: settings) }
        var xpBefore = 0.0
        let leveled = oldestFirst.map { session in
            var session = session
            session.levelWhenPlayed = level(forXP: xpBefore, startingLevel: settings.startingLevel).level
            xpBefore += session.xp
            return session
        }
        return leveled.reversed()
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
        guard rules.allowsSlowTrack(on: session.date) else { return (.normal, .campaignRule) }
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

    // MARK: - XP

    private func normalXP(of session: PlayedSession, kind: AdventureKind) -> (Double, XPSource) {
        if let xp = rules.normalXP(for: kind) { return (xp, .rules) }
        return (estimatedXP(from: session.points, isGameMaster: session.isGameMaster), .estimated)
    }

    /// Achievement Points are the adventure's XP times the event's multiplier (1 to 2), doubled for the GM,
    /// and slow track doesn't change them. Scenario-sized XP is tried first, being the most common.
    func estimatedXP(from points: SessionPoints, isGameMaster: Bool) -> Double {
        let base = points.achievementPoints / (isGameMaster ? 2 : 1)
        let candidates: [Double] = [4, 12, 2, 1]
        return candidates.first { Self.eventMultipliers.contains(base / $0) } ?? 0
    }

    private static let eventMultipliers: Set<Double> = [1, 1.25, 1.5, 1.75, 2]
}

/// A character's level and how far it is through it.
public struct CharacterLevel: Hashable, Sendable {
    public let level: Int
    public let xp: Double
    public let xpIntoLevel: Double
    public let xpPerLevel: Double

    public var fractionIntoLevel: Double { min(xpIntoLevel / xpPerLevel, 1) }
}
