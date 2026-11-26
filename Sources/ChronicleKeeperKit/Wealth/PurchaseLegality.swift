import Foundation

/// Why a purchase may not be Society legal where it sits in the ledger (R5.7). Only level and rarity are checked.
/// The user says what gives Access by linking the purchase to a boon or a Chronicle Sheet (`AccessLink`, R5.10);
/// the limited and restricted lists come later.
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
            "\(rarity.rawValue.capitalized): needs Access, such as from a boon or a Chronicle Sheet."
        }
    }

    /// The reason as it reads once the user has linked the purchase to what allows it.
    public func explanation(coveredBy link: AccessLink) -> String {
        switch self {
        case let .aboveLevel(itemLevel, limit):
            "Level \(itemLevel): above the highest item level the character could buy here (\(limit)), "
                + "allowed by \(link.sourceDescription)."
        case .notCommon(let rarity):
            "\(rarity.rawValue.capitalized): Access from \(link.sourceDescription)."
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

    /// Why a marked purchase has its warning, in a sentence each.
    public static func warning(for marks: [LegalityMark]) -> String {
        (["This purchase may not be Society legal."] + marks.map(\.explanation)).joined(separator: " ")
    }

    /// What a linked purchase's check says: each mark the link waives, or only the link when nothing is marked
    /// (the purchase was moved or edited since).
    public static func explanation(of marks: [LegalityMark], coveredBy link: AccessLink) -> String {
        guard !marks.isEmpty else { return "Linked to \(link.sourceDescription)." }
        return marks.map { $0.explanation(coveredBy: link) }.joined(separator: " ")
    }
}
