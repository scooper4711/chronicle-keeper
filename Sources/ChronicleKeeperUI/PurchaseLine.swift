import ChronicleKeeperKit
import SwiftUI

/// A purchase: name, quantity and its sign, what it cost, and its menu. Draggable onto another group (R5.5). A
/// marked purchase can be linked to the boon or Chronicle Sheet that makes it legal, from its sign or its menu
/// (R5.10).
struct PurchaseLine: View {
    let purchase: Purchase
    let marks: [LegalityMark]
    let line: LedgerLine
    let context: LedgerContext
    let edit: () -> Void
    @State private var isLinking = false

    var body: some View {
        LedgerLineLayout(balance: line.balance, column: .boughtAndSold, context: context) {
            label
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
        .sheet(isPresented: $isLinking) {
            AccessLinkPicker(purchase: purchase, record: context.record, store: context.store)
        }
    }

    /// Marked, and nothing linked that allows it: the warning sign and orange text (R5.7).
    private var isWarned: Bool { purchase.accessLink == nil && !marks.isEmpty }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                ItemIcon(itemID: purchase.itemID)
                sign
                Text(purchase.name + (purchase.quantity > 1 ? " ×\(purchase.quantity)" : ""))
                    .foregroundStyle(isWarned ? Color.orange : Color.primary)
                    .help(isWarned ? PurchaseLegality.warning(for: marks) : "")
                    .accessibilityLabel(purchase.name + (purchase.quantity > 1 ? ", \(purchase.quantity) of them" : ""))
            }
            conflictNote
        }
    }

    /// A check for a linked purchase, whatever its marks; otherwise a warning for a marked one.
    @ViewBuilder private var sign: some View {
        if let link = purchase.accessLink {
            AccessCheck(marks: marks, link: link, unlink: unlink)
        } else if !marks.isEmpty {
            LegalityWarning(marks: marks) { isLinking = true }
        }
    }

    /// Says when the boon covers another purchase too, which two devices can do before they sync.
    @ViewBuilder private var conflictNote: some View {
        let use = AccessLinkUse(
            characterNumber: context.record.id, characterName: context.record.name, purchase: purchase)
        let note = context.links.conflictNote(for: use)
        if !note.isEmpty {
            Text(note).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var menu: some View {
        Button("Edit…", action: edit)
        linkButton
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

    /// The way to link and unlink for the keyboard and VoiceOver.
    @ViewBuilder private var linkButton: some View {
        if let link = purchase.accessLink {
            Button(link.unlinkTitle, action: unlink)
        } else if !marks.isEmpty {
            Button(LegalityWarning.linkTitle) { isLinking = true }
        }
    }

    private func unlink() {
        context.store.unlink(purchase.id, of: context.record.id)
    }
}
