import Foundation

/// Why a purchase may not be Society legal where it sits in the ledger (R5.7). Version 1 checks only level and
/// rarity; Access from boons and Chronicles, and the limited and restricted lists, come later.
public enum LegalityMark: Hashable, Sendable {
    /// The item's level is above what the character could buy at that point.
    case aboveLevel(itemLevel: Int, limit: Int)
    /// The item isn't common, so it needs Access.
    case notCommon(Rarity)

    /// The reason in words, for help text and VoiceOver.
    public var explanation: String {
        switch self {
        case let .aboveLevel(itemLevel, limit):
            "Level \(itemLevel): above the highest item level the character could buy here (\(limit))."
        case .notCommon(let rarity):
            "\(rarity.rawValue.capitalized): needs Access, such as from a Chronicle."
        }
    }
}

/// The Purchasing Guidelines of the Guide to Organized Play: a character may buy common items (or items they have
/// Access to) "of item level equal to or lower than their character level", where a character below 2nd level
/// counts as 2nd.
public enum PurchaseLegality {
    public static let minimumItemLevelLimit = 2

    /// The highest item level a character of this level may buy.
    public static func itemLevelLimit(characterLevel: Int) -> Int {
        max(characterLevel, minimumItemLevelLimit)
    }

    /// The marks on a purchase made by a character of this level; empty when nothing is wrong.
    public static func marks(for purchase: Purchase, characterLevel: Int) -> [LegalityMark] {
        var marks: [LegalityMark] = []
        let limit = itemLevelLimit(characterLevel: characterLevel)
        if purchase.level > limit { marks.append(.aboveLevel(itemLevel: purchase.level, limit: limit)) }
        if purchase.rarity != .common { marks.append(.notCommon(purchase.rarity)) }
        return marks
    }
}
