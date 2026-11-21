import ChronicleKeeperKit
import SwiftUI

/// What the user adds about a character: default track, starting level, a character sheet link and notes.
/// A refresh never touches these.
struct CharacterSettingsForm: View {
    let record: CharacterRecord
    let store: CharacterStore
    @Environment(\.portraits) private var portraits
    @State private var isReadingPortrait = false

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
            if startingLevels.count > 1 {
                LabeledContent("Starting level") {
                    Picker("Starting level", selection: binding(\.startingLevel)) {
                        ForEach(startingLevels, id: \.self) { Text("Level \($0)").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .help("The level the character began play at; Paizo allows 1st, 3rd, 5th or 7th")
            }
            TextField("Character sheet link", text: binding(\.characterSheetLink),
                      prompt: Text("https://… (Pathbuilder, Demiplane, Foundry, a PDF)"))
            if let sheet = DemiplanePortraitSource.sheetURL(from: record.settings.characterSheetURL) {
                Button("Use Portrait from Demiplane") { usePortrait(from: sheet) }
                    .disabled(isReadingPortrait)
            }
            TextField("Notes", text: binding(\.notes), axis: .vertical)
                .lineLimit(3...8)
        }
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 520, alignment: .leading)
    }

    private func usePortrait(from sheet: URL) {
        isReadingPortrait = true
        Task {
            let editor = PortraitEditor(number: record.id, store: store, portraits: portraits)
            await editor.usePortrait(fromSheet: sheet, source: .forApp)
            isReadingPortrait = false
        }
    }

    private var startingLevels: [Int] {
        CampaignRules(campaign: record.campaign).startingLevels
    }

    private func binding<Value>(_ path: WritableKeyPath<CharacterSettings, Value>) -> Binding<Value> {
        Binding(
            get: { record.settings[keyPath: path] },
            set: { value in store.update(record.id) { $0[keyPath: path] = value } })
    }
}
