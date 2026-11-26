import Foundation

/// A purchase that is linked to a boon or a Chronicle Sheet, and whose purchase it is.
public struct AccessLinkUse: Hashable, Sendable, Identifiable {
    public let characterNumber: String
    public let characterName: String
    public let purchase: Purchase

    public init(characterNumber: String, characterName: String, purchase: Purchase) {
        self.characterNumber = characterNumber
        self.characterName = characterName
        self.purchase = purchase
    }

    public var id: String { "\(characterNumber)/\(purchase.id)" }

    /// "Abendego's Cannon (Ryo Mousehunter)".
    public var description: String { "\(purchase.name) (\(characterName))" }
}

extension [AccessLinkUse] {
    /// "Abendego's Cannon (Ryo Mousehunter), Wayfinder (Korbul Thornbrook)".
    public var summary: String { map(\.description).joined(separator: ", ") }
}

/// Every linked purchase of every character, by what it is linked to (R5.10). A boon covers one purchase across the
/// whole account, so linking one has to know where it is used already.
public struct AccessLinkIndex: Sendable {
    private let uses: [String: [AccessLinkUse]]

    public init(characters: [CharacterRecord]) {
        var uses: [String: [AccessLinkUse]] = [:]
        for character in characters.sorted(by: { ($0.name, $0.id) < ($1.name, $1.id) }) {
            let purchases = character.settings.wealth.purchases.values
                .sorted { ($0.addedAt, $0.id) < ($1.addedAt, $1.id) }
            for purchase in purchases {
                guard let link = purchase.accessLink else { continue }
                uses[link.key, default: []].append(AccessLinkUse(
                    characterNumber: character.id, characterName: character.name, purchase: purchase))
            }
        }
        self.uses = uses
    }

    /// The purchases linked to this boon or Chronicle Sheet, by character and then in the order they were added.
    public func uses(of link: AccessLink) -> [AccessLinkUse] {
        uses[link.key] ?? []
    }

    /// The other purchases linked to the boon this purchase is linked to. There are some only when two devices
    /// each linked the boon before they synced; a Chronicle Sheet may be shared, so it has none.
    public func rivals(of use: AccessLinkUse) -> [AccessLinkUse] {
        guard let link = use.purchase.accessLink, link.kind == .boon else { return [] }
        return uses(of: link).filter { $0.id != use.id }
    }

    /// What to tell the user when the purchase's boon is linked to another purchase too; empty when it isn't.
    public func conflictNote(for use: AccessLinkUse) -> String {
        let rivals = rivals(of: use)
        guard !rivals.isEmpty else { return "" }
        return "This boon is also linked to \(rivals.summary). A boon covers one purchase, so unlink one of them."
    }
}
