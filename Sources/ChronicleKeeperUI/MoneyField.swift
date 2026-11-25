import ChronicleKeeperKit
import SwiftUI

/// An amount in the ledger, right-aligned digits, in red when it is negative: a balance below zero.
struct MoneyText: View {
    let amount: Int
    let context: LedgerContext

    var body: some View {
        LedgerFigure(text: context.format(amount), isNegative: amount < 0)
    }
}

/// What a line changed: "+0.5 gp" for a sale, "−1 gp" in red for a purchase.
struct MoneyChangeText: View {
    let amount: Int
    let context: LedgerContext

    var body: some View {
        LedgerFigure(text: context.formatChange(amount), isNegative: amount < 0)
    }
}

/// A figure as the ledger shows it.
private struct LedgerFigure: View {
    let text: String
    let isNegative: Bool

    var body: some View {
        Text(text).monospacedDigit().lineLimit(1).foregroundStyle(isNegative ? Color.red : Color.primary)
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
            .frame(maxWidth: LedgerColumn.income)
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
