import ChronicleKeeperKit
import SwiftUI

/// A ledger line's columns: what it is, what it changed and the balance after it, and its menu. On one line when
/// there's room, on two on an iPhone.
struct LedgerLineLayout<Label: View, Amount: View, Actions: View>: View {
    let balance: Int
    let context: LedgerContext
    @ViewBuilder let label: () -> Label
    @ViewBuilder let amount: () -> Amount
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                label().frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                figures
            }
            VStack(alignment: .leading, spacing: 4) {
                label()
                HStack(spacing: 10) { Spacer(minLength: 0); figures }
            }
        }
        .font(.callout)
    }

    private var figures: some View {
        HStack(spacing: 10) {
            amount().frame(minWidth: 110, alignment: .trailing)
            Text(context.format(balance))
                .monospacedDigit()
                .foregroundStyle(balance < 0 ? Color.red : Color.secondary)
                .frame(minWidth: 100, alignment: .trailing)
                .accessibilityLabel("Balance \(context.format(balance))")
            actions().frame(width: 28)
        }
    }
}

/// The line a group opens with: the starting funds, or the field for what an adventure gave (R5.1, R5.2).
struct OpeningLine: View {
    let group: LedgerGroup
    let line: LedgerLine
    let context: LedgerContext

    var body: some View {
        LedgerLineLayout(balance: line.balance, context: context) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title).lineLimit(2)
                if case .session = group.place {
                    Text("Level \(group.characterLevel)").font(.caption).foregroundStyle(.secondary)
                }
            }
        } amount: {
            field
        } actions: {
            EmptyView()
        }
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
        LedgerLineLayout(balance: line.balance, context: context) {
            name
        } amount: {
            Text(context.formatChange(line.amount)).monospacedDigit()
        } actions: {
            Menu { menu } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Actions for \(purchase.name)")
        }
        .contentShape(Rectangle())
        .contextMenu { menu }
        .draggable(LedgerDragItem(kind: .purchase, purchaseID: purchase.id).text)
    }

    /// A marked item has a star and orange text, with the reason as help text and for VoiceOver (R5.7).
    private var name: some View {
        HStack(spacing: 4) {
            if !marks.isEmpty {
                Image(systemName: "star.fill").foregroundStyle(.orange).accessibilityHidden(true)
            }
            Text(purchase.name + (purchase.quantity > 1 ? " ×\(purchase.quantity)" : ""))
                .foregroundStyle(marks.isEmpty ? Color.primary : Color.orange)
        }
        .help(explanation)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(purchase.name + (purchase.quantity > 1 ? ", \(purchase.quantity) of them" : ""))
        .accessibilityValue(explanation)
    }

    private var explanation: String {
        marks.map(\.explanation).joined(separator: " ")
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

/// A sale, under the adventure it followed: "Sold: Longsword" and what it brought back (R5.4).
struct SaleLine: View {
    let purchase: Purchase
    let line: LedgerLine
    let context: LedgerContext

    var body: some View {
        LedgerLineLayout(balance: line.balance, context: context) {
            Text("Sold: \(purchase.name)" + (purchase.quantity > 1 ? " ×\(purchase.quantity)" : ""))
                .foregroundStyle(.secondary)
        } amount: {
            Text(context.formatChange(line.amount)).monospacedDigit()
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

/// One button per place a line can go: starting funds and each adventure, from `from` on when given.
struct DestinationButtons: View {
    let context: LedgerContext
    let from: String?
    let choose: (String) -> Void

    var body: some View {
        ForEach(context.destinations(from: from)) { group in
            Button(group.title) { choose(group.id) }
        }
    }
}

/// A money amount typed by hand. Empty means none (nil); text that doesn't read as money is put back as it was.
/// Saved on Return and when the field loses focus.
struct MoneyField: View {
    let label: String
    let amount: Int?
    let placeholder: String
    let currency: Currency
    let commit: (Int?) -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(label, text: $text, prompt: Text(placeholder))
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 120)
            .focused($isFocused)
            #if os(iOS)
            .keyboardType(.numbersAndPunctuation)
            #endif
            .onSubmit(save)
            .onChange(of: isFocused) { _, focused in if !focused { save() } }
            .onChange(of: amount) { _, _ in if !isFocused { text = shown } }
            .onAppear { text = shown }
            .accessibilityLabel(label)
    }

    private var shown: String {
        amount.map { Money.format($0, in: currency) } ?? ""
    }

    private func save() {
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard typed != shown else { return }
        if typed.isEmpty { return commit(nil) }
        guard let value = Money.parse(typed, in: currency) else {
            text = shown
            return
        }
        commit(value)
        text = Money.format(value, in: currency)
    }
}
