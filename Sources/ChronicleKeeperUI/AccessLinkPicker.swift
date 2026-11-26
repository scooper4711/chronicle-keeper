import ChronicleKeeperKit
import SwiftUI

/// Chooses the boon or the Chronicle Sheet that makes a purchase legal (R5.10): those of the buyer first, then of
/// the other characters in the same campaign. A boon that covers another purchase is dimmed, and choosing it asks
/// before the link moves.
struct AccessLinkPicker: View {
    let purchase: Purchase
    let record: CharacterRecord
    let store: CharacterStore
    @Environment(\.dismiss) private var dismiss
    @State private var kind = AccessLink.Kind.boon
    @State private var search = ""
    /// A boon that is linked already, while the user is asked whether to move it.
    @State private var taken: AccessLinkOption?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                controls
                list
            }
            .navigationTitle("Link \(purchase.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .alert("Move the Link?", isPresented: isAsking, presenting: taken) { option in
            Button("Move Link") { choose(option) }
            Button("Cancel", role: .cancel) {}
        } message: { option in
            Text(option.moveQuestion(to: purchase))
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }

    private var isAsking: Binding<Bool> {
        Binding { taken != nil } set: { if !$0 { taken = nil } }
    }

    private var groups: [AccessLinkGroup] {
        AccessLinkOptions(roster: store.roster, buyer: record, kind: kind).groups(matching: search)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Link to", selection: $kind) {
                Text("Boons").tag(AccessLink.Kind.boon)
                Text("Chronicle Sheets").tag(AccessLink.Kind.chronicle)
            }
            .pickerStyle(.segmented).labelsHidden()
            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("access-link-search")
            Text("Choose what gives \(record.name) this item. Chronicle Keeper doesn't check that it does: "
                 + "you vouch for it.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding()
    }

    private var list: some View {
        let groups = groups
        return List {
            if groups.isEmpty {
                Text(emptyText).foregroundStyle(.secondary)
            }
            ForEach(groups) { group in
                Section(group.characterName) {
                    ForEach(group.options) { option in
                        AccessLinkRow(option: option) { pick(option) }
                    }
                }
            }
        }
    }

    private var emptyText: String {
        let things = kind == .boon ? "boons" : "adventures"
        guard search.trimmingCharacters(in: .whitespaces).isEmpty else { return "No \(things) match “\(search)”." }
        return "No \(things) on paizo.com for characters in \(record.campaign.displayName)."
    }

    private func pick(_ option: AccessLinkOption) {
        if option.isTaken { taken = option } else { choose(option) }
    }

    private func choose(_ option: AccessLinkOption) {
        store.link(purchase.id, of: record.id, to: option.link)
        dismiss()
    }
}

/// One boon or Chronicle Sheet in the picker, with the purchases it is linked to already.
private struct AccessLinkRow: View {
    let option: AccessLinkOption
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).foregroundStyle(option.isTaken ? .secondary : .primary)
                    if let day = option.day {
                        Text(day.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if !option.uses.isEmpty {
                    Text("used for \(option.uses.summary)")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(option.isTaken ? "Linked already. Choosing it asks before the link moves." : "")
    }
}
