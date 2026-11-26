import Foundation

/// One boon or Chronicle Sheet a purchase can be linked to.
public struct AccessLinkOption: Hashable, Sendable, Identifiable {
    public let link: AccessLink
    /// The boon's name, or the adventure's title with its levels.
    public let title: String
    /// When a Chronicle Sheet's session was played, which tells two sessions of one adventure apart; nil for a boon
    /// and for a session without a date.
    public let day: Date?
    /// The purchases linked to it already.
    public let uses: [AccessLinkUse]

    public var id: String { link.key }

    /// Whether choosing it takes it from another purchase: a boon covers one purchase, a Chronicle Sheet any number.
    public var isTaken: Bool { link.kind == .boon && !uses.isEmpty }

    /// What to ask before a boon is taken from the purchase it covers now.
    public func moveQuestion(to purchase: Purchase) -> String {
        "\(title) is linked to \(uses.summary). A boon covers one purchase. Move it to \(purchase.name)?"
    }
}

/// One character's boons or Chronicle Sheets.
public struct AccessLinkGroup: Hashable, Sendable, Identifiable {
    public let characterNumber: String
    public let characterName: String
    public let options: [AccessLinkOption]

    public var id: String { characterNumber }
}

/// What a purchase can be linked to (R5.10): the boons, or the Chronicle Sheets, of the characters in the buyer's
/// campaign, the buyer's own first and the others by name. A boon may be claimed by one character and used by
/// another, so the others' are offered too; another campaign's never are.
public struct AccessLinkOptions: Sendable {
    /// Each character that has any, the buyer first.
    public let groups: [AccessLinkGroup]

    public init(roster: CharacterRoster, buyer: CharacterRecord, kind: AccessLink.Kind) {
        let index = AccessLinkIndex(characters: roster.characters)
        let others = roster.characters(in: buyer.campaign).filter { $0.id != buyer.id }
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
        groups = ([buyer] + others).map { character in
            let options = switch kind {
            case .boon: Self.boons(of: character, in: roster, index: index)
            case .chronicle: Self.chronicles(of: character, index: index)
            }
            return AccessLinkGroup(characterNumber: character.id, characterName: character.name, options: options)
        }.filter { !$0.options.isEmpty }
    }

    /// The groups narrowed to what the text names: a character's name keeps all of theirs, otherwise only the
    /// titles that hold it. Empty text keeps everything.
    public func groups(matching text: String) -> [AccessLinkGroup] {
        let wanted = text.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return groups }
        return groups.compactMap { group in
            if group.characterName.localizedCaseInsensitiveContains(wanted) { return group }
            let options = group.options.filter { $0.title.localizedCaseInsensitiveContains(wanted) }
            return options.isEmpty ? nil : AccessLinkGroup(
                characterNumber: group.characterNumber, characterName: group.characterName, options: options)
        }
    }

    private static func boons(
        of character: CharacterRecord, in roster: CharacterRoster, index: AccessLinkIndex
    ) -> [AccessLinkOption] {
        roster.boons(for: character.id).map { boon in
            let link = AccessLink(boon: boon)
            return AccessLinkOption(link: link, title: boon.name, day: nil, uses: index.uses(of: link))
        }
    }

    /// Newest first, as the adventures table lists them.
    private static func chronicles(of character: CharacterRecord, index: AccessLinkIndex) -> [AccessLinkOption] {
        character.sessions.map { progress in
            let link = AccessLink(session: progress.session, of: character)
            return AccessLinkOption(link: link, title: progress.session.adventure.titleWithLevels,
                                    day: progress.date.day, uses: index.uses(of: link))
        }
    }
}
