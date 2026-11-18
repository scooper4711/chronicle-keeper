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
        let leveled = oldestFirst.map { session -> SessionProgress in
            var session = session
            session.levelWhenPlayed = level(forXP: xpBefore, startingLevel: settings.startingLevel).level
            let range = AdventureClassifier.levelRange(of: session.session.adventure)
            (session.creditLevel, session.isOutOfLevelRange) = creditLevel(session.levelWhenPlayed, in: range)
            let applied = appliedXP(
                of: session, xpBefore: xpBefore, startingLevel: settings.startingLevel,
                levelWhenPlayed: session.levelWhenPlayed)
            session.xpLost = session.xp - applied
            xpBefore += applied
            return session
        }
        return leveled.reversed()
    }

    /// The level a session's credit counts as applied at, and whether that took clamping: when the character's
    /// level at the time falls outside the adventure's own range, a sign they played a pregen, or were GM, with
    /// the Guide's "Applying Credit" rules crediting it away from that range (held for a later level, or a
    /// pregen's level used instead), the nearest level inside the range stands in for the pregen's own level.
    /// An adventure with no known range credits the level as played, never clamped.
    private func creditLevel(_ levelWhenPlayed: Int, in range: LevelRange?) -> (level: Int, wasClamped: Bool) {
        guard let range, !range.contains(levelWhenPlayed) else { return (levelWhenPlayed, false) }
        return (min(max(levelWhenPlayed, range.lowest), range.highest), true)
    }

    /// The XP a session actually banks toward leveling. "Normally, Chronicles are applied as soon as they are
    /// issued" in full; the Guide's cap only matters for a *held* Chronicle (the character was below the
    /// adventure's own range when they played it, so it waited for them to catch up): "a character's level
    /// cannot exceed the level of any Chronicle applied to them", so XP that would carry them past the
    /// adventure's own highest level is lost. A session played in or above its range, or with no known range,
    /// banks its XP in full; so does a held one not yet near that ceiling.
    private func appliedXP(
        of session: SessionProgress, xpBefore: Double, startingLevel: Int, levelWhenPlayed: Int
    ) -> Double {
        guard let range = AdventureClassifier.levelRange(of: session.session.adventure),
              levelWhenPlayed < range.lowest else { return session.xp }
        let start = rules.startingLevel(startingLevel)
        let ceiling = Double(range.highest + 1 - start) * rules.xpPerLevel - Self.levelCapEpsilon
        return max(0, min(session.xp, ceiling - xpBefore))
    }

    /// Comfortably smaller than the smallest XP award (a slow-track quest's half point), so the ceiling above
    /// excludes the next level's first XP value without excluding any real award just below it.
    private static let levelCapEpsilon = 0.000_001

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
