import ChronicleKeeperKit
import SwiftUI

/// Adds or edits a purchase (R5.3). Typing a name lists up to eight items from the item data right under the field
/// (plain rows, no popover, so focus behaves on the Mac and the iPad); Return takes the first. Picking one fills
/// its price, level and rarity; the price stays editable, to override it. A name that matches nothing is a custom
/// item, with its own price, level and rarity.
struct PurchaseEditor: View {
    let initial: Purchase
    let currency: Currency
    let game: ItemGame?
    let save: (Purchase) -> Void
    let cancel: () -> Void
    @State private var draft: Purchase
    @State private var name: String
    @State private var priceText: String
    /// Matches for what was typed, worked out once per change of the name rather than on every redraw.
    @State private var suggestions: [PricedItem] = []
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
            // Item, quantity and price on one line; the price drops below when the pane is too narrow.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { nameField.frame(minWidth: 160); quantityField; priceField }
                VStack(alignment: .leading, spacing: 8) {
                    nameField
                    HStack(spacing: 12) { quantityField; priceField }
                }
            }
            ItemSuggestions(items: suggestions, currency: currency, pick: pick)
            PriceNote(catalogPrice: catalogItem?.price, price: price, isCustom: isUnmatched,
                      currency: currency) { catalogPrice in
                priceText = Money.format(catalogPrice, in: currency)
            }
            if isCustom { CustomItemFields(level: $draft.level, rarity: $draft.rarity) }
            buttons
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .onAppear { isNameFocused = initial.name.isEmpty }
    }

    /// Lists matches for what was typed; none once an item is picked and its name left alone.
    private func refreshSuggestions() {
        guard let game, !isShowingPickedItem else {
            suggestions = []
            return
        }
        suggestions = ItemPriceList.bundled.suggestions(for: name, game: game)
    }

    private var isShowingPickedItem: Bool { !draft.itemID.isEmpty && name == draft.name }

    private var isCustom: Bool { draft.itemID.isEmpty }

    /// A name typed that nothing in the item data matches: a custom item.
    private var isUnmatched: Bool { isCustom && !trimmedName.isEmpty && suggestions.isEmpty }

    /// The picked item as the item data has it, for its catalog price.
    private var catalogItem: PricedItem? {
        guard !isCustom else { return nil }
        return ItemPriceList.bundled.item(id: draft.itemID)
    }

    private var price: Int? { Money.parse(priceText, in: currency) }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var nameField: some View {
        TextField("Item", text: $name, prompt: Text("Item name"))
            .textFieldStyle(.roundedBorder)
            .focused($isNameFocused)
            .onSubmit { suggestions.first.map(pick) }
            .onChange(of: name) { _, typed in
                if typed != draft.name { draft.itemID = "" }
                refreshSuggestions()
            }
            .accessibilityIdentifier("purchase-name")
    }

    /// "Qty", a short field and a stepper: typing suits 50 arrows, the stepper a second potion.
    private var quantityField: some View {
        HStack(spacing: 4) {
            Text("Qty").foregroundStyle(.secondary)
            TextField("Quantity", value: $draft.quantity, format: .number)
                .textFieldStyle(.roundedBorder).monospacedDigit().multilineTextAlignment(.trailing)
                .frame(width: 48)
                .onChange(of: draft.quantity) { _, typed in draft.quantity = Self.allowedQuantities.clamp(typed) }
                .accessibilityLabel("Quantity")
            Stepper("Quantity", value: $draft.quantity, in: Self.allowedQuantities).labelsHidden()
        }
        .fixedSize()
    }

    private static let allowedQuantities = 1...999

    private var priceField: some View {
        TextField("Price each", text: $priceText, prompt: Text("Price each, e.g. 0.05 gp"))
            .textFieldStyle(.roundedBorder).monospacedDigit()
            .frame(minWidth: 110, maxWidth: 170)
            .accessibilityLabel("Price of one")
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
        draft.name = item.purchaseName
        draft.level = item.level
        draft.rarity = item.rarity
        name = item.purchaseName
        priceText = Money.format(item.price, in: currency)
        suggestions = []
    }

    private func finish() {
        guard let price else { return }
        var purchase = draft
        purchase.name = trimmedName
        purchase.unitPrice = price
        save(purchase)
    }
}

/// Says whose price this is: the item data's, an override of it (with a way back), or a custom item's.
struct PriceNote: View {
    let catalogPrice: Int?
    let price: Int?
    let isCustom: Bool
    let currency: Currency
    let useCatalogPrice: (Int) -> Void

    var body: some View {
        if let catalogPrice, let price, price != catalogPrice {
            HStack {
                Text("Your price overrides the item data's \(Money.format(catalogPrice, in: currency)).")
                Button("Use \(Money.format(catalogPrice, in: currency))") { useCatalogPrice(catalogPrice) }
                    .buttonStyle(.borderless)
            }
            .font(.caption).foregroundStyle(.secondary)
        } else if isCustom {
            Text("Nothing in the item data matches: this is a custom item with your own price, level and rarity.")
                .font(.caption).foregroundStyle(.secondary)
        }
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

private extension ClosedRange where Bound == Int {
    func clamp(_ value: Int) -> Int { Swift.min(Swift.max(value, lowerBound), upperBound) }
}
