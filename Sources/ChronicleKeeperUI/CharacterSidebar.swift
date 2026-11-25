import ChronicleKeeperKit
import SwiftUI

/// Every character, grouped by campaign.
struct CharacterSidebar: View {
    let roster: CharacterRoster
    @Binding var selection: CharacterRecord.ID?

    var body: some View {
        List(selection: $selection) {
            ForEach(roster.campaigns, id: \.self) { campaign in
                Section(campaign.displayName) {
                    ForEach(roster.characters(in: campaign)) { record in
                        CharacterRow(record: record).tag(record.id)
                    }
                }
            }
            if !roster.unmatchedSessions.isEmpty || !roster.unmatchedBoons.isEmpty {
                Section("Not Matched") {
                    if !roster.unmatchedSessions.isEmpty {
                        unmatched("\(roster.unmatchedSessions.count) sessions belong to no character on your "
                                  + "Summary tab")
                    }
                    ForEach(roster.unmatchedBoons) { boon in
                        unmatched("Boon \(boon.name) for \(boon.characterName): no single character has that name")
                    }
                }
            }
        }
        .navigationTitle("Characters")
    }

    private func unmatched(_ text: String) -> some View {
        Label(text, systemImage: "questionmark.circle")
            .foregroundStyle(.secondary)
            .font(.caption)
    }
}

/// A character's portrait, name, number and level.
struct CharacterRow: View {
    let record: CharacterRecord

    var body: some View {
        HStack(spacing: 10) {
            PortraitView(record: record, side: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.name).font(.headline).lineLimit(1)
                Text(record.id).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                LevelSummary(level: record.level, compact: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// "Lv 5 · 7/12 XP" with a bar showing the way to the next level.
struct LevelSummary: View {
    let level: CharacterLevel
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Lv \(level.level) · \(XPText.of(level.xpIntoLevel))/\(XPText.of(level.xpPerLevel)) XP")
                .font(compact ? .caption : .subheadline)
                .monospacedDigit()
            ProgressView(value: level.fractionIntoLevel)
                .progressViewStyle(.linear)
                .frame(maxWidth: compact ? 120 : 260)
                .accessibilityLabel("Progress to level \(level.level + 1)")
        }
    }
}
