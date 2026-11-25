import ChronicleKeeperKit
import SwiftUI

/// Adds or edits a purchase (R5.3). Typing a name lists up to eight items from the item data right under the field
/// (plain rows, no popover, so focus behaves on the Mac and the iPad); Return takes the first. Picking one fills
/// its price, level and rarity. A name that matches nothing is an item typed by hand, with its own price.
struct PurchaseEditor: View {
    let initial: Purchase
    let currency: Currency
    let game: ItemGame?
    let save: (Purchase) -> Void
    let cancel: () -> Void
    @State private var draft: Purchase
    @State private var name: String
    @State private var priceText: String
    @FocusState private var isNameFocused: Bool

    init(
        initial: Purchase, currency: Currency, game: ItemGame?,
        save: @escaping (Purchase) -> Void, cancel: @escaping () -> Void
    ) {
        self.initial = initial
        self.currency = currency
        self.game = game
        self.save = save
        self.cancel = cancel
        _draft = State(initialValue: initial)
        _name = State(initialValue: initial.name)
        _priceText = State(initialValue: initial.name.isEmpty ? "" : Money.format(initial.unitPrice, in: currency))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Item", text: $name, prompt: Text("Item name"))
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onSubmit { suggestions.first.map(pick) }
                .onChange(of: name) { _, typed in if typed != draft.name { draft.itemID = "" } }
                .accessibilityIdentifier("purchase-name")
            ItemSuggestions(items: suggestions, currency: currency, pick: pick)
            details
            if isCustom { CustomItemFields(level: $draft.level, rarity: $draft.rarity) }
            buttons
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .onAppear { isNameFocused = initial.name.isEmpty }
    }

    /// Matches for what was typed; none once an item is picked and its name left alone.
    private var suggestions: [PricedItem] {
        guard let game, !(draft.itemID.isEmpty == false && name == draft.name) else { return [] }
        return ItemPriceList.bundled.suggestions(for: name, game: game)
    }

    private var isCustom: Bool { draft.itemID.isEmpty }

    private var price: Int? { Money.parse(priceText, in: currency) }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var details: some View {
        HStack(spacing: 12) {
            TextField("Price each", text: $priceText, prompt: Text("Price each"))
                .textFieldStyle(.roundedBorder).monospacedDigit().frame(maxWidth: 150)
                .accessibilityLabel("Price of one")
            Stepper("Quantity: \(draft.quantity)", value: $draft.quantity, in: 1...999).fixedSize()
        }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
            Button(initial.name.isEmpty ? "Add" : "Save", action: finish)
                .buttonStyle(.borderedProminent)
                .disabled(trimmedName.isEmpty || price == nil)
        }
    }

    private func pick(_ item: PricedItem) {
        draft.itemID = item.id
        draft.name = item.name
        draft.level = item.level
        draft.rarity = item.rarity
        name = item.name
        priceText = Money.format(item.price, in: currency)
    }

    private func finish() {
        guard let price else { return }
        var purchase = draft
        purchase.name = trimmedName
        purchase.unitPrice = price
        save(purchase)
    }
}

/// The items matching what was typed, one plain row each.
struct ItemSuggestions: View {
    let items: [PricedItem]
    let currency: Currency
    let pick: (PricedItem) -> Void

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    Button { pick(item) } label: { row(item) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Fills in the item's price and level")
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func row(_ item: PricedItem) -> some View {
        HStack {
            Text(item.name)
            if item.rarity != .common {
                Text(item.rarity.rawValue.capitalized).font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            Text("Level \(item.level)").font(.caption).foregroundStyle(.secondary)
            Text(Money.format(item.price, in: currency) + (item.batchSize > 1 ? " for \(item.batchSize)" : ""))
                .monospacedDigit().frame(minWidth: 90, alignment: .trailing)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

/// Level and rarity of an item typed by hand, which the legality marks need (R5.7).
struct CustomItemFields: View {
    @Binding var level: Int
    @Binding var rarity: Rarity

    var body: some View {
        HStack(spacing: 12) {
            Stepper("Item level: \(level)", value: $level, in: 0...30).fixedSize()
            Picker("Rarity", selection: $rarity) {
                ForEach(Rarity.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .fixedSize()
        }
        .font(.callout)
    }
}
