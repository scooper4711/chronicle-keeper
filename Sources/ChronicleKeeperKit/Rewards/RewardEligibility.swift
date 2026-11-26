import Foundation

/// A free reward a character may claim on paizo.com and hasn't yet (R3.9).
public struct ClaimableReward: Hashable, Sendable, Identifiable {
    /// The reward, or an adventure's lettered boons ("Boon A", "Boon B"), of which the Chronicle Sheet says which
    /// one was earned: claiming one rules out the others.
    public let offers: [RewardOffer]
    /// Why it is free now, in words.
    public let reason: String
    /// The sessions that earned it; empty for a reward earned another way.
    public let sessionIDs: [String]
    /// The faction whose reputation earned it, as the Summary tab names it; empty for a reward earned another way.
    public let faction: String

    public var id: String { offers.first?.id ?? "" }
    public var isChoice: Bool { offers.count > 1 }

    /// The reward's name, or the adventure's with its choices: "… Bandits of Immenwood: Boon A or Boon B".
    public var title: String {
        guard isChoice, let first = offers.first else { return offers.first?.name ?? "" }
        let letters = offers.map { RewardName.letter(of: $0.name) }.joined(separator: " or ")
        return "\(RewardName.withoutLetter(first.name)): \(letters)"
    }
}

/// Works out which of the free rewards a character may claim: the ones whose condition the account shows is met,
/// and that the character doesn't have.
public struct RewardEligibility: Sendable {
    /// Rewards that are claimed together or not at all: one reward, or an adventure's lettered boons.
    private struct Group: Sendable {
        var offers: [RewardOffer]
        let requirement: RewardRequirement
        var campaign: Campaign { offers[0].campaign }
        var names: Set<String> { Set(offers.map { RewardName.key($0.name) }) }
    }

    private let groups: [Group]

    /// Reads every reward's condition once: a catalog is checked against each character in turn.
    public init(catalog: RewardCatalog) {
        var groups: [Group] = []
        var places: [String: Int] = [:]
        for offer in catalog.offers {
            let key = "\(offer.campaign.shortName)|\(offer.kind.rawValue)|\(RewardName.choiceKey(offer.name))"
            if let place = places[key] {
                groups[place].offers.append(offer)
            } else {
                places[key] = groups.count
                groups.append(Group(offers: [offer], requirement: RewardRequirementParser.requirement(of: offer)))
            }
        }
        self.groups = groups
    }

    /// The rewards the character may claim, in the lists' order. `owned` are the character's boons as the Boons tab
    /// lists them: having one of an adventure's lettered boons rules out the others.
    public func claimable(for record: CharacterRecord, owned: [Boon]) -> [ClaimableReward] {
        let ownedNames = Set(owned.map { RewardName.key($0.name) })
        let claimant = Claimant(record)
        return groups
            .filter { $0.campaign == record.campaign && $0.names.isDisjoint(with: ownedNames) }
            .compactMap { group in
                claimant.earning(group.requirement).map { earning in
                    ClaimableReward(offers: group.offers, reason: earning.reason,
                                    sessionIDs: earning.sessionIDs, faction: earning.faction)
                }
            }
    }
}

/// How a character met a requirement.
struct Earning {
    var reason: String
    var sessionIDs: [String] = []
    var faction = ""
}

/// A character as the requirements see it, with its adventures' codes and names worked out once.
struct Claimant {
    let played: [PlayedAdventure]
    let factions: [NamedValue]

    init(_ record: CharacterRecord) {
        // paizo.com hands a reward out only for a session it has (R1.14).
        played = record.sessions.filter(\.isReported).map(PlayedAdventure.init)
        factions = record.summary.factions
    }

    /// How the character met the requirement, or nil when it didn't or the app can't tell.
    func earning(_ requirement: RewardRequirement) -> Earning? {
        switch requirement {
        case .played(let adventures, let needsAll): playing(adventures, needsAll: needsAll)
        case .reputation(let points, let faction): standing(points, with: faction)
        case .sessions(let count): sessions(atLeast: count)
        case .unknown: nil
        }
    }

    private func playing(_ adventures: [RewardAdventure], needsAll: Bool) -> Earning? {
        let found = adventures.map { adventure in played.filter(adventure.matches) }
        let isMet = needsAll ? found.allSatisfy { !$0.isEmpty } : found.contains { !$0.isEmpty }
        let sessions = found.flatMap(\.self)
        guard isMet, let first = sessions.first else { return nil }
        let titles = needsAll ? found.compactMap(\.first?.title) : [first.title]
        return Earning(reason: "You played \(titles.joined(separator: " and "))", sessionIDs: sessions.map(\.sessionID))
    }

    private func standing(_ points: Int, with faction: String) -> Earning? {
        let candidates = faction.isEmpty ? factions : factions.filter { Self.isFaction($0.name, named: faction) }
        guard let best = candidates.max(by: { $0.value < $1.value }), best.value >= points else { return nil }
        let reason = "You have \(best.value) reputation with \(best.name); it takes \(points)"
        return Earning(reason: reason, faction: best.name)
    }

    private func sessions(atLeast count: Int) -> Earning? {
        guard count > 0, played.count >= count else { return nil }
        return Earning(reason: "You have played \(played.count) sessions; it takes \(count)")
    }

    /// Whether the Summary tab's faction is the one a condition names. The lists shorten some names: "Second
    /// Seekers (Ehu)" is the Summary's "Second Seekers (Ehu Hadif)".
    static func isFaction(_ summaryName: String, named required: String) -> Bool {
        let wanted = fold(required)
        return !wanted.isEmpty && fold(summaryName).hasPrefix(wanted)
    }

    private static func fold(_ name: String) -> String {
        let folded = String(name.lowercased().filter { $0.isLetter || $0.isNumber })
        return folded.hasPrefix("the") ? String(folded.dropFirst(3)) : folded
    }
}
