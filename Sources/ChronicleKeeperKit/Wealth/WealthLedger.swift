import Foundation

/// One line of the ledger, with the balance after it.
public struct LedgerLine: Hashable, Sendable, Identifiable {
    public enum Entry: Hashable, Sendable {
        case startingFunds(Int)
        /// The gold an adventure gave, or nil when the field is empty (counted as nothing).
        case earned(Int?)
        case purchase(Purchase, marks: [LegalityMark])
        case sale(Purchase)
    }

    public let entry: Entry
    /// The balance after this line, in copper.
    public let balance: Int

    public var id: String {
        switch entry {
        case .startingFunds: "start"
        case .earned: "earned"
        case .purchase(let purchase, _): "purchase-\(purchase.id)"
        case .sale(let purchase): "sale-\(purchase.id)"
        }
    }

    /// What this line adds to the balance (negative for a purchase).
    public var amount: Int {
        switch entry {
        case .startingFunds(let amount): amount
        case .earned(let amount): amount ?? 0
        case .purchase(let purchase, _): -purchase.cost
        case .sale(let purchase): purchase.saleValue
        }
    }
}

/// A run of lines: starting gold, one adventure, or the purchases whose adventure paizo.com no longer lists.
public struct LedgerGroup: Hashable, Sendable, Identifiable {
    public enum Place: Hashable, Sendable {
        case start
        case session(SessionProgress)
        case unlisted
    }

    public let place: Place
    public let lines: [LedgerLine]
    /// The character's level after this group's credit, which purchases in it are checked against.
    public let characterLevel: Int

    /// The key purchases in this group carry in `boughtAfter` and `soldAfter`.
    public var id: String {
        switch place {
        case .start: ""
        case .session(let progress): progress.session.keyWithinCharacter
        case .unlisted: "unlisted"
        }
    }
}

/// A character's ledger worked out from their record (R5.6): starting funds, then for each adventure, oldest first
/// in the order credit was banked, the gold it gave, the sales and then the purchases made after it.
public struct WealthLedger: Sendable {
    public let currency: Currency
    public let groups: [LedgerGroup]
    /// The order of the groups' keys, for moving purchases and sales.
    public let order: LedgerOrder
    /// How many adventures have no gold entered, so the balance is incomplete (R5.2).
    public let adventuresWithoutGold: Int

    /// The balance after the last line.
    public var balance: Int { groups.last?.lines.last?.balance ?? 0 }

    /// Whether the balance went below zero anywhere (R5.6).
    public var isOverspent: Bool {
        groups.contains { $0.lines.contains { $0.balance < 0 } }
    }

    public init(record: CharacterRecord) {
        let rules = CampaignRules(campaign: record.campaign)
        let places = Self.places(of: record)
        let wealth = record.settings.wealth
        let builder = GroupBuilder(wealth: wealth, rules: rules, record: record)
        var balance = 0
        groups = places.map { builder.group(for: $0, balance: &balance) }.filter { group in
            group.place != .unlisted || !group.lines.isEmpty
        }
        currency = rules.currency
        order = LedgerOrder(keys: places.compactMap(\.sessionKey))
        adventuresWithoutGold = record.sessions.filter {
            wealth.earned[$0.session.keyWithinCharacter] == nil
        }.count
    }

    private static func places(of record: CharacterRecord) -> [LedgerGroup.Place] {
        let sessions = record.sessions.sorted { $0.applyOrder < $1.applyOrder }
        return [.start] + sessions.map { .session($0) } + [.unlisted]
    }
}

extension LedgerGroup.Place {
    var sessionKey: String? {
        if case .session(let progress) = self { return progress.session.keyWithinCharacter }
        return nil
    }
}

/// Builds each group's lines and keeps the running balance.
private struct GroupBuilder {
    let wealth: CharacterWealth
    let rules: CampaignRules
    let record: CharacterRecord
    let knownKeys: Set<String>

    init(wealth: CharacterWealth, rules: CampaignRules, record: CharacterRecord) {
        self.wealth = wealth
        self.rules = rules
        self.record = record
        knownKeys = Set(record.sessions.map(\.session.keyWithinCharacter) + [""])
    }

    func group(for place: LedgerGroup.Place, balance: inout Int) -> LedgerGroup {
        let level = characterLevel(at: place)
        var entries = [opening(of: place)].compactMap { $0 }
        entries += purchases(in: place) { $0.soldAfter }.map { LedgerLine.Entry.sale($0) }
        entries += purchases(in: place) { $0.boughtAfter }.map {
            LedgerLine.Entry.purchase($0, marks: PurchaseLegality.marks(for: $0, characterLevel: level))
        }
        let lines = entries.map { entry in
            let line = LedgerLine(entry: entry, balance: balance + LedgerLine(entry: entry, balance: 0).amount)
            balance = line.balance
            return line
        }
        return LedgerGroup(place: place, lines: lines, characterLevel: level)
    }

    private func opening(of place: LedgerGroup.Place) -> LedgerLine.Entry? {
        switch place {
        case .start:
            .startingFunds(wealth.startingFunds ?? rules.startingFunds(level: record.settings.startingLevel))
        case .session(let progress):
            .earned(wealth.earned[progress.session.keyWithinCharacter])
        case .unlisted:
            nil
        }
    }

    /// The purchases whose key (`boughtAfter` or `soldAfter`) puts them in this group, in the order added.
    private func purchases(in place: LedgerGroup.Place, keyedBy key: (Purchase) -> String?) -> [Purchase] {
        wealth.purchases.values.filter { purchase in
            guard let value = key(purchase) else { return false }
            switch place {
            case .start: return value.isEmpty
            case .session(let progress): return value == progress.session.keyWithinCharacter
            case .unlisted: return !knownKeys.contains(value)
            }
        }.sorted { ($0.addedAt, $0.id) < ($1.addedAt, $1.id) }
    }

    private func characterLevel(at place: LedgerGroup.Place) -> Int {
        switch place {
        case .start: rules.startingLevel(record.settings.startingLevel)
        case .session(let progress):
            ProgressCalculator(campaign: record.campaign)
                .level(forXP: progress.totalXP, startingLevel: record.settings.startingLevel).level
        case .unlisted: record.level.level
        }
    }
}
