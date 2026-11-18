import Foundation

/// Applies every session's XP in the order the Guide to Organized Play's "Applying Credit" rules give it, not
/// simply the order played:
///
/// - A session played within, or above, its adventure's own level range is applied immediately, in full, as
///   it's played ("Normally, Chronicles are applied as soon as they are issued").
/// - A session played *below* its adventure's range is held (queued, in the order played) until the character's
///   level reaches that range. Held sessions are then applied as a batch, in the order they were earned, each
///   capped so it can't carry the character's level past that specific adventure's own highest level: "a
///   character's level cannot exceed the level of any Chronicle applied to them, [so] any out-of-level
///   Chronicles applied are lost."
struct CreditApplier {
    private let rules: CampaignRules
    private let startingLevel: Int
    private let levelOf: (Double) -> Int

    init(rules: CampaignRules, startingLevel: Int, levelOf: @escaping (Double) -> Int) {
        self.rules = rules
        self.startingLevel = startingLevel
        self.levelOf = levelOf
    }

    /// `sessions` is oldest first; the result keeps that same position for every session (so the date order the
    /// caller expects is undisturbed), even though a held session's credit lands later, out of turn. Each
    /// session's `applyOrder` records when its credit actually landed.
    func apply(to sessions: [SessionProgress]) -> [SessionProgress] {
        var resolved = [SessionProgress?](repeating: nil, count: sessions.count)
        var held: [(index: Int, session: SessionProgress)] = []
        var bankedXP = 0.0
        var order = 0

        for (index, session) in sessions.enumerated() {
            let levelBefore = levelOf(bankedXP)
            let range = AdventureClassifier.levelRange(of: session.session.adventure)
            if let range, levelBefore < range.lowest {
                held.append((index, holding(session, levelWhenPlayed: levelBefore)))
            } else {
                order += 1
                resolved[index] = applyImmediately(
                    session, levelWhenPlayed: levelBefore, order: order, bankedXP: &bankedXP)
            }
            while let next = held.first, isEligible(next.session, bankedXP: bankedXP) {
                held.removeFirst()
                order += 1
                resolved[next.index] = applyHeld(next.session, order: order, bankedXP: &bankedXP)
            }
        }
        for leftover in held {
            order += 1
            resolved[leftover.index] = neverReached(leftover.session, order: order, bankedXP: bankedXP)
        }
        return resolved.compactMap { $0 }
    }

    private func isEligible(_ session: SessionProgress, bankedXP: Double) -> Bool {
        guard let range = AdventureClassifier.levelRange(of: session.session.adventure) else { return true }
        return levelOf(bankedXP) >= range.lowest
    }

    private func holding(_ session: SessionProgress, levelWhenPlayed: Int) -> SessionProgress {
        var session = session
        session.levelWhenPlayed = levelWhenPlayed
        session.isOutOfLevelRange = true
        return session
    }

    private func applyImmediately(
        _ session: SessionProgress, levelWhenPlayed: Int, order: Int, bankedXP: inout Double
    ) -> SessionProgress {
        var session = session
        session.levelWhenPlayed = levelWhenPlayed
        session.creditLevel = levelWhenPlayed
        bankedXP += session.xp
        session.totalXP = bankedXP
        session.applyOrder = order
        return session
    }

    /// Applies one held session now that the character has caught up to its range, capping it at the adventure's
    /// own highest level: the excess, if any, is lost. `creditLevel` is the level the character was at when the
    /// credit landed — walking in, before this session's own XP is added — not the level it leaves them at.
    private func applyHeld(_ session: SessionProgress, order: Int, bankedXP: inout Double) -> SessionProgress {
        var session = session
        session.creditLevel = levelOf(bankedXP)
        guard let range = AdventureClassifier.levelRange(of: session.session.adventure) else {
            bankedXP += session.xp
            session.totalXP = bankedXP
            session.applyOrder = order
            return session
        }
        let start = rules.startingLevel(startingLevel)
        let ceiling = Double(range.highest + 1 - start) * rules.xpPerLevel - Self.levelCapEpsilon
        let applied = max(0, min(session.xp, ceiling - bankedXP))
        session.xpLost = session.xp - applied
        bankedXP += applied
        session.totalXP = bankedXP
        session.applyOrder = order
        return session
    }

    /// A held session the character never caught back up to: its credit was never banked.
    private func neverReached(_ session: SessionProgress, order: Int, bankedXP: Double) -> SessionProgress {
        var session = session
        if let range = AdventureClassifier.levelRange(of: session.session.adventure) {
            session.creditLevel = range.lowest
        }
        session.xpLost = session.xp
        session.totalXP = bankedXP
        session.applyOrder = order
        return session
    }

    /// Comfortably smaller than the smallest XP award (a slow-track quest's half point), so the ceiling above
    /// excludes the next level's first XP value without excluding any real award just below it.
    private static let levelCapEpsilon = 0.000_001
}
