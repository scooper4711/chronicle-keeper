import ChronicleKeeperKit
import SwiftUI

/// The widths of the ledger's number columns, so every amount lines up under its header like a spreadsheet.
enum LedgerColumn {
    static let income: CGFloat = 110
    static let change: CGFloat = 90
    static let balance: CGFloat = 90
    static let actions: CGFloat = 24
    static let spacing: CGFloat = 8
    static let minimumLabel: CGFloat = 120
}

/// Which column a line's amount goes in: money coming in (treasure and earned income), or bought and sold.
enum LedgerAmountColumn {
    case income
    case boughtAndSold
}

/// A ledger line's columns: what it is, money coming in (treasure and earned income), money spent or got back from
/// a sale, the balance after it, and its menu. The label wraps inside its column, so the figures stay under their
/// titles; only where even the columns don't fit (an iPhone) do the figures go on a second line, without the empty
/// column.
struct LedgerLineLayout<Label: View, Amount: View, Actions: View>: View {
    let balance: Int
    let column: LedgerAmountColumn
    let context: LedgerContext
    @ViewBuilder let label: () -> Label
    @ViewBuilder let amount: () -> Amount
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: LedgerColumn.spacing) {
                // A small ideal width, so ViewThatFits measures the label as wrapped rather than on one line.
                label().frame(minWidth: LedgerColumn.minimumLabel, idealWidth: LedgerColumn.minimumLabel,
                              maxWidth: .infinity, alignment: .leading)
                incomeCell
                changeCell
                balanceAndActions
            }
            VStack(alignment: .leading, spacing: 4) {
                label()
                HStack(spacing: LedgerColumn.spacing) {
                    Spacer(minLength: 0)
                    if column == .income { incomeCell } else { changeCell }
                    balanceAndActions
                }
            }
        }
        .font(.callout)
    }

    private var incomeCell: some View {
        Group { if column == .income { amount() } else { Text("") } }
            .frame(width: LedgerColumn.income, alignment: .trailing)
    }

    private var changeCell: some View {
        Group { if column == .income { Text("") } else { amount() } }
            .frame(width: LedgerColumn.change, alignment: .trailing)
    }

    private var balanceAndActions: some View {
        HStack(spacing: LedgerColumn.spacing) {
            MoneyText(amount: balance, context: context)
                .frame(width: LedgerColumn.balance, alignment: .trailing)
                .accessibilityLabel("Balance \(context.format(balance))")
            actions().frame(width: LedgerColumn.actions)
        }
    }
}

/// The column titles over the ledger's lines.
struct LedgerHeader: View {
    let currency: Currency

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: LedgerColumn.spacing) {
                Text("Adventure or Item")
                    .frame(minWidth: LedgerColumn.minimumLabel, idealWidth: LedgerColumn.minimumLabel,
                           maxWidth: .infinity, alignment: .leading)
                Text(currency == .credits ? "Credits & Earned Income" : "Treasure & Earned Income")
                    .frame(width: LedgerColumn.income, alignment: .trailing)
                Text("Bought & Sold").frame(width: LedgerColumn.change, alignment: .trailing)
                Text("Balance").frame(width: LedgerColumn.balance, alignment: .trailing)
                Text("").frame(width: LedgerColumn.actions)
            }
            // Where the columns don't fit, each line puts its figures on a second line and needs no titles. A
            // real view, since ViewThatFits skips an EmptyView and would keep the row that is too wide.
            Color.clear.frame(width: 0, height: 0)
        }
        .multilineTextAlignment(.trailing)
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
    }
}

/// The line a group opens with: the starting funds, or the field for what an adventure gave (R5.1, R5.2).
struct OpeningLine: View {
    let group: LedgerGroup
    let line: LedgerLine
    let context: LedgerContext

    var body: some View {
        LedgerLineLayout(balance: line.balance, column: .income, context: context) {
            Text(label)
        } amount: {
            field
        } actions: {
            // Holds the menu's column, so this balance lines up with those of the purchases.
            Text("")
        }
    }

    /// Words as the chronicle has them.
    private var label: String {
        let money = context.currency == .credits ? "credits" : "gold"
        return group.place == .start ? "Starting \(money)" : "\(money.capitalized) earned"
    }

    @ViewBuilder private var field: some View {
        switch group.place {
        case .start:
            let campaignAmount = context.rules.startingFunds(level: context.record.settings.startingLevel)
            MoneyField(label: "Starting funds", amount: context.wealth.startingFunds,
                       placeholder: context.format(campaignAmount), currency: context.currency) { amount in
                context.change { wealth, _ in wealth.startingFunds = amount }
            }
        case .session(let progress):
            let key = group.id
            MoneyField(label: "Earned on \(group.title)", amount: context.wealth.earned[key],
                       placeholder: hint(for: progress), currency: context.currency) { amount in
                context.change { wealth, _ in wealth.earned[key] = amount }
            }
        case .unlisted:
            EmptyView()
        }
    }

    /// The most the adventure could have given at the level it was played, only as a hint (R5.2).
    private func hint(for progress: SessionProgress) -> String {
        context.rules.fundsHint(level: progress.levelWhenPlayed).map { "up to \(context.format($0))" }
            ?? "From the chronicle"
    }
}

/// A purchase: name, quantity and any marks, what it cost, and its menu. Draggable onto another group (R5.5).
struct PurchaseLine: View {
    let purchase: Purchase
    let marks: [LegalityMark]
    let line: LedgerLine
    let context: LedgerContext
    let edit: () -> Void

    var body: some View {
        LedgerLineLayout(balance: line.balance, column: .boughtAndSold, context: context) {
            name
        } amount: {
            MoneyChangeText(amount: line.amount, context: context)
        } actions: {
            Menu { menu } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Actions for \(purchase.name)")
        }
        .contentShape(Rectangle())
        .contextMenu { menu }
        .draggable(LedgerDragItem(kind: .purchase, purchaseID: purchase.id).text)
    }

    /// A marked item has a warning sign that explains itself, and orange text (R5.7).
    private var name: some View {
        HStack(spacing: 4) {
            ItemIcon(itemID: purchase.itemID)
            if !marks.isEmpty { LegalityWarning(marks: marks) }
            Text(purchase.name + (purchase.quantity > 1 ? " ×\(purchase.quantity)" : ""))
                .foregroundStyle(marks.isEmpty ? Color.primary : Color.orange)
                .help(marks.isEmpty ? "" : LegalityWarning.explanation(of: marks))
                .accessibilityLabel(purchase.name + (purchase.quantity > 1 ? ", \(purchase.quantity) of them" : ""))
        }
    }

    @ViewBuilder private var menu: some View {
        Button("Edit…", action: edit)
        if !purchase.isSold {
            Menu("Sell After") {
                DestinationButtons(context: context, from: purchase.boughtAfter) { key in
                    context.change { wealth, order in wealth.sell(purchase.id, after: key, in: order) }
                }
            }
        }
        Menu("Move To") {
            DestinationButtons(context: context, from: nil) { key in
                context.change { wealth, order in wealth.move(purchase.id, to: key, in: order) }
            }
        }
        Divider()
        Button("Remove", role: .destructive) {
            context.change { wealth, _ in wealth.remove(purchase.id) }
        }
    }
}

/// The sign on a purchase that may not be Society legal. Hovering shows why on the Mac and with an iPad's pointer;
/// tapping or clicking shows it in a popover, which is how the iPhone and a touch-only iPad see it.
struct LegalityWarning: View {
    let marks: [LegalityMark]
    @State private var isShowingWhy = false

    var body: some View {
        Button { isShowingWhy = true } label: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .buttonStyle(.borderless)
        .help(Self.explanation(of: marks))
        .accessibilityLabel("May not be Society legal")
        .accessibilityHint(marks.map(\.explanation).joined(separator: " "))
        .popover(isPresented: $isShowingWhy) {
            Text(Self.explanation(of: marks))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 300, alignment: .leading)
                .padding()
                .presentationCompactAdaptation(.popover)
        }
    }

    static func explanation(of marks: [LegalityMark]) -> String {
        (["This purchase may not be Society legal."] + marks.map(\.explanation)).joined(separator: " ")
    }
}

/// A sale, under the adventure it followed: "Sold: Longsword" and what it brought back (R5.4).
struct SaleLine: View {
    let purchase: Purchase
    let line: LedgerLine
    let context: LedgerContext

    var body: some View {
        LedgerLineLayout(balance: line.balance, column: .boughtAndSold, context: context) {
            HStack(spacing: 4) {
                ItemIcon(itemID: purchase.itemID).opacity(0.6)
                Text("Sold: \(purchase.name)" + (purchase.quantity > 1 ? " ×\(purchase.quantity)" : ""))
                    .foregroundStyle(.secondary)
            }
        } amount: {
            MoneyChangeText(amount: line.amount, context: context)
        } actions: {
            Menu { menu } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Actions for the sale of \(purchase.name)")
        }
        .contentShape(Rectangle())
        .contextMenu { menu }
        .draggable(LedgerDragItem(kind: .sale, purchaseID: purchase.id).text)
    }

    @ViewBuilder private var menu: some View {
        Menu("Move To") {
            DestinationButtons(context: context, from: purchase.boughtAfter) { key in
                context.change { wealth, order in wealth.sell(purchase.id, after: key, in: order) }
            }
        }
        Button("Undo Sale") {
            context.change { wealth, _ in wealth.undoSale(of: purchase.id) }
        }
    }
}

/// One button per place a line can go: starting funds and each adventure, from `from` on when given. When there's
/// none, says what to do instead of showing an empty menu.
struct DestinationButtons: View {
    let context: LedgerContext
    let from: String?
    let choose: (String) -> Void

    var body: some View {
        let groups = context.destinations(from: from)
        if groups.isEmpty {
            // A purchase whose adventure paizo.com no longer lists can't be placed against the others.
            Text("Move the purchase to an adventure first")
        }
        ForEach(groups) { group in
            Button(group.title) { choose(group.id) }
        }
    }
}
