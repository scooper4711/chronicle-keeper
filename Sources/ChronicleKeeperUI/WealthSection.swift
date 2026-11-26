import ChronicleKeeperKit
import SwiftUI

/// The character's gold and purchases (R5): the balance, notes on what may be wrong with it, then the ledger,
/// oldest first in the order credit was banked.
struct WealthSection: View {
    let record: CharacterRecord
    let store: CharacterStore

    var body: some View {
        let context = LedgerContext(record: record, store: store)
        CollapsibleSection(context.currency == .credits ? "Credits & Purchases" : "Gold & Purchases",
                           id: "wealth") {
            balance(context)
        } content: {
            LedgerNotes(ledger: context.ledger, currency: context.currency)
            VStack(alignment: .leading, spacing: 0) {
                LedgerHeader(currency: context.currency).padding(.bottom, 4)
                let groups = Array(zip(context.ledger.groups, Self.firstRows(of: context.ledger)))
                ForEach(groups, id: \.0.id) { group, firstRow in
                    Divider()
                    LedgerGroupView(group: group, firstRow: firstRow, context: context)
                }
            }
        }
        // Reads the item data (about 1 MB) off the main thread before the first purchase is added.
        .task { await Task.detached(priority: .utility) { _ = ItemPriceList.bundled.items.count }.value }
    }

    /// Where each group's lines start when every line of the ledger is counted, so the stripes alternate across
    /// groups as a spreadsheet's rows do.
    private static func firstRows(of ledger: WealthLedger) -> [Int] {
        var next = 0
        return ledger.groups.map { group in
            defer { next += group.lines.count }
            return next
        }
    }

    private func balance(_ context: LedgerContext) -> some View {
        Text(context.format(context.ledger.balance))
            .font(.headline).monospacedDigit()
            .foregroundStyle(context.ledger.balance < 0 ? Color.red : Color.primary)
            .accessibilityLabel("Balance: \(context.format(context.ledger.balance))")
    }
}

/// Says when the balance went below zero, and how many adventures have no gold entered (R5.2, R5.6).
struct LedgerNotes: View {
    let ledger: WealthLedger
    let currency: Currency

    var body: some View {
        if ledger.isOverspent {
            Label("The balance drops below zero. Move a purchase to after a later adventure, or check the "
                  + "\(money) entered.", systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.red)
        }
        if ledger.adventuresWithoutGold > 0 {
            Text(missingText).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var money: String { currency == .credits ? "credits" : "gold" }

    private var missingText: String {
        let count = ledger.adventuresWithoutGold
        let adventures = count == 1 ? "1 adventure has" : "\(count) adventures have"
        return "\(adventures) no \(money) entered yet, so the balance may be short. "
            + "Type what each chronicle gave."
    }
}

/// What the ledger's views share: the character, the worked-out ledger, and how to change it.
@MainActor
struct LedgerContext {
    let record: CharacterRecord
    let store: CharacterStore
    let ledger: WealthLedger
    let rules: CampaignRules
    /// Where each boon and Chronicle Sheet is used, on every character (R5.10).
    let links: AccessLinkIndex

    init(record: CharacterRecord, store: CharacterStore) {
        self.record = record
        self.store = store
        ledger = WealthLedger(record: record)
        rules = CampaignRules(campaign: record.campaign)
        links = store.accessLinks
    }

    var currency: Currency { ledger.currency }
    var wealth: CharacterWealth { record.settings.wealth }

    func format(_ copper: Int) -> String {
        Money.format(copper, in: currency)
    }

    /// "+5 sp" for money coming in, "−1 gp" for money going out.
    func formatChange(_ copper: Int) -> String {
        (copper > 0 ? "+" : "") + format(copper)
    }

    func change(_ edit: (inout CharacterWealth, LedgerOrder) -> Void) {
        store.update(record.id) { edit(&$0.wealth, ledger.order) }
    }

    /// Where a purchase or sale can go: starting gold and every adventure, oldest first; with `from`, only from that
    /// key on.
    func destinations(from key: String? = nil) -> [LedgerGroup] {
        ledger.groups.filter { group in
            group.place != .unlisted
                && key.map { ledger.order.position(of: group.id) >= ledger.order.position(of: $0) } ?? true
        }
    }
}

extension LedgerGroup {
    /// The group's name in the ledger and in menus.
    var title: String {
        switch place {
        case .start: "Before the First Adventure"
        case .session(let progress): progress.session.adventure.titleWithLevels
        case .unlisted: "Adventures paizo.com no longer lists"
        }
    }
}

/// One group of the ledger: its opening line (starting funds or an adventure's gold field), its sales and
/// purchases, and a way to add one. Purchases and sales can be dropped on it to move them here (R5.5).
struct LedgerGroupView: View {
    let group: LedgerGroup
    /// The ledger-wide number of this group's first line, for the stripes.
    let firstRow: Int
    let context: LedgerContext
    @State private var isAdding = false
    @State private var editingID: String?
    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupTitle(group: group)
            ForEach(Array(group.lines.enumerated()), id: \.element.id) { index, line in
                row(for: line)
                    .padding(.horizontal, 6).padding(.vertical, 5)
                    .background((firstRow + index).isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.05))
            }
            addOrEdit.padding(6)
        }
        .background(isDropTarget ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .dropDestination(for: String.self) { items, _ in drop(items) } isTargeted: { isDropTarget = $0 }
    }

    @ViewBuilder private func row(for line: LedgerLine) -> some View {
        switch line.entry {
        case .startingFunds, .earned:
            OpeningLine(group: group, line: line, context: context)
        case let .purchase(purchase, marks):
            if editingID == purchase.id {
                editor(for: purchase)
            } else {
                PurchaseLine(purchase: purchase, marks: marks, line: line, context: context) {
                    editingID = purchase.id
                }
            }
        case .sale(let purchase):
            SaleLine(purchase: purchase, line: line, context: context)
        }
    }

    @ViewBuilder private var addOrEdit: some View {
        if isAdding {
            editor(for: Purchase(name: "", unitPrice: 0, boughtAfter: group.id))
        } else if group.place != .unlisted {
            Button { isAdding = true } label: { Label("Add Purchase", systemImage: "plus") }
                .buttonStyle(.borderless).font(.callout)
                .accessibilityHint("Adds a purchase made after \(group.title)")
        }
    }

    /// Edits a purchase in place; a new one is saved only when the user adds it.
    private func editor(for purchase: Purchase) -> some View {
        PurchaseEditor(initial: purchase, currency: context.currency,
                       game: ItemGame(campaign: context.record.campaign)) { saved in
            context.change { wealth, _ in wealth.add(saved) }
            close()
        } cancel: {
            close()
        }
    }

    private func close() {
        isAdding = false
        editingID = nil
    }

    private func drop(_ items: [String]) -> Bool {
        guard group.place != .unlisted, let item = items.first.flatMap(LedgerDragItem.init) else { return false }
        context.change { wealth, order in
            switch item.kind {
            case .purchase: wealth.move(item.purchaseID, to: group.id, in: order)
            case .sale: wealth.sell(item.purchaseID, after: group.id, in: order)
            }
        }
        return true
    }
}

/// A group's name in bold across all the columns, with the character's level there for an adventure.
struct GroupTitle: View {
    let group: LedgerGroup

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(group.title).font(.callout.bold())
            if case .session = group.place {
                Text("Level \(group.characterLevel)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 2)
        .accessibilityAddTraits(.isHeader)
    }
}

/// What a dragged purchase or sale line carries: "purchase:<id>" or "sale:<id>".
struct LedgerDragItem {
    enum Kind: String { case purchase, sale }

    let kind: Kind
    let purchaseID: String

    init(kind: Kind, purchaseID: String) {
        self.kind = kind
        self.purchaseID = purchaseID
    }

    init?(_ text: String) {
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = Kind(rawValue: parts[0]) else { return nil }
        self.init(kind: kind, purchaseID: parts[1])
    }

    var text: String { "\(kind.rawValue):\(purchaseID)" }
}
