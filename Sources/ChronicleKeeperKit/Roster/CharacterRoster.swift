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
    /// When each session counts as played, worked out from the whole account's sessions.
    public let eventDates: EventDates
    /// Each character's boons, by character number.
    public private(set) var boonsByCharacter: [String: [Boon]] = [:]
    /// Boons whose character name matches no character, or more than one.
    public private(set) var unmatchedBoons: [Boon] = []

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
        // From every session, as another character's session can be the one that dates an event.
        let eventDates = EventDates(sessions: sessions)
        characters = summaries.map { summary in
            let calculator = ProgressCalculator(campaign: summary.campaign, eventDates: eventDates)
            let settings = settings[summary.number] ?? CharacterSettings()
            let progress = calculator.history(of: byNumber[summary.number] ?? [], settings: settings)
            return Self.record(summary, progress, settings)
        }
        unmatchedSessions = unmatched
        self.eventDates = eventDates
    }

    /// Gives each boon to the character it names. The Boons tab shows only names, so a name two characters share
    /// leaves the boon unmatched rather than guessing.
    public mutating func attach(_ boons: [Boon]) {
        let byName = Dictionary(grouping: characters) { $0.name.lowercased() }
        boonsByCharacter = [:]
        unmatchedBoons = []
        for boon in boons {
            if let matches = byName[boon.characterName.lowercased()], matches.count == 1 {
                boonsByCharacter[matches[0].id, default: []].append(boon)
            } else {
                unmatchedBoons.append(boon)
            }
        }
    }

    public func boons(for number: String) -> [Boon] {
        boonsByCharacter[number] ?? []
    }

    public func characters(in campaign: Campaign) -> [CharacterRecord] {
        characters.filter { $0.campaign == campaign }
    }

    /// The campaigns that have characters, in sidebar order.
    public var campaigns: [Campaign] {
        Array(Set(characters.map(\.campaign))).sorted { $0.sortOrder < $1.sortOrder }
    }

    private static func record(
        _ summary: CharacterSummary, _ progress: [SessionProgress], _ settings: CharacterSettings
    ) -> CharacterRecord {
        let calculator = ProgressCalculator(campaign: summary.campaign)
        // Lost XP (the Guide's "Applying Credit" level cap) never counts toward the total.
        let xp = progress.reduce(0) { $0 + $1.xp - $1.xpLost }
        let level = calculator.level(forXP: xp, startingLevel: settings.startingLevel)
        return CharacterRecord(summary: summary, sessions: progress, level: level, settings: settings)
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
