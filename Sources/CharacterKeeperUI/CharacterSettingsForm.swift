import CharacterKeeperKit
import SwiftUI

/// What the user adds about a character: default track, an XP adjustment, a character sheet link and notes.
/// A refresh never touches these.
struct CharacterSettingsForm: View {
    let record: CharacterRecord
    let store: CharacterStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Notes and Corrections").font(.headline)
            // Labeled outside the picker: a menu picker on iOS shows only its value.
            LabeledContent("Default track") {
                Picker("Default track", selection: binding(\.defaultTrack)) {
                    ForEach(Track.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            .help("The track for sessions that don't show which track they were played on")
            LabeledContent("XP adjustment") {
                TextField("0", value: binding(\.xpAdjustment), format: .number)
                    .frame(width: 80)
                    .help("XP that paizo.com doesn't show, such as from boons; may be negative")
            }
            TextField("Character sheet link", text: binding(\.characterSheetLink),
                      prompt: Text("https://… (Pathbuilder, Demiplane, Foundry, a PDF)"))
            TextField("Notes", text: binding(\.notes), axis: .vertical)
                .lineLimit(3...8)
        }
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 520, alignment: .leading)
    }

    private func binding<Value>(_ path: WritableKeyPath<CharacterSettings, Value>) -> Binding<Value> {
        Binding(
            get: { record.settings[keyPath: path] },
            set: { value in store.update(record.id) { $0[keyPath: path] = value } })
    }
}
