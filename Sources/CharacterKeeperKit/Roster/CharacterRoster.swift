import Foundation

/// A character with its sessions, XP and level.
public struct CharacterRecord: Hashable, Sendable, Identifiable {
    public let summary: CharacterSummary
    /// Newest first.
    public let sessions: [SessionProgress]
    public let level: CharacterLevel
    public let settings: CharacterSettings

    public var id: String { summary.number }
    public var campaign: Campaign { summary.campaign }
    public var name: String { summary.name }
}

/// Every character with the sessions that belong to it, and the sessions no character could be found for.
public struct CharacterRoster: Sendable {
    public let characters: [CharacterRecord]
    public let unmatchedSessions: [PlayedSession]

    public init(
        summaries: [CharacterSummary], sessions: [PlayedSession], settings: [String: CharacterSettings] = [:]
    ) {
        let matcher = CharacterMatcher(summaries: summaries)
        var byNumber: [String: [PlayedSession]] = [:]
        var unmatched: [PlayedSession] = []
        for session in sessions {
            if let number = matcher.characterNumber(for: session) {
                byNumber[number, default: []].append(session)
            } else {
                unmatched.append(session)
            }
        }
        characters = summaries.map { summary in
            Self.record(summary, byNumber[summary.number] ?? [], settings[summary.number] ?? CharacterSettings())
        }
        unmatchedSessions = unmatched
    }

    public func characters(in campaign: Campaign) -> [CharacterRecord] {
        characters.filter { $0.campaign == campaign }
    }

    /// The campaigns that have characters, in sidebar order.
    public var campaigns: [Campaign] {
        Array(Set(characters.map(\.campaign))).sorted { $0.sortOrder < $1.sortOrder }
    }

    private static func record(
        _ summary: CharacterSummary, _ sessions: [PlayedSession], _ settings: CharacterSettings
    ) -> CharacterRecord {
        let calculator = ProgressCalculator(campaign: summary.campaign)
        let progress = sessions
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .map { calculator.progress(of: $0, settings: settings) }
        let xp = progress.reduce(settings.xpAdjustment) { $0 + $1.xp }
        return CharacterRecord(summary: summary, sessions: progress, level: calculator.level(forXP: xp), settings: settings)
    }
}

/// Finds the character a session belongs to. Played sessions name the character number; sessions the player
/// ran name only the player, so those are matched by character name within the campaign.
struct CharacterMatcher {
    private let numbers: Set<String>
    private let byNameAndCampaign: [String: [String]]

    init(summaries: [CharacterSummary]) {
        numbers = Set(summaries.map(\.number))
        byNameAndCampaign = Dictionary(grouping: summaries, by: { Self.key($0.name, $0.campaign) })
            .mapValues { $0.map(\.number) }
    }

    func characterNumber(for session: PlayedSession) -> String? {
        if let number = session.characterNumber {
            return numbers.contains(number) ? number : nil
        }
        let candidates = byNameAndCampaign[Self.key(session.characterName, session.campaign)] ?? []
        return candidates.count == 1 ? candidates[0] : nil
    }

    private static func key(_ name: String, _ campaign: Campaign) -> String {
        "\(campaign.shortName)|\(name.lowercased())"
    }
}
