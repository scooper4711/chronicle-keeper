import ChronicleKeeperKit
import SwiftUI

/// "Who can play…?": pick an adventure, see which characters haven't played it and are inside its levels.
struct AdventureFinderView: View {
    let roster: CharacterRoster
    let select: (CharacterRecord.ID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var adventure: AdventureEntry?

    private var catalog: AdventureCatalog {
        AdventureCatalog(sessions: roster.characters.flatMap { $0.sessions.map(\.session) })
    }

    var body: some View {
        NavigationStack {
            Group {
                if let adventure {
                    CandidateList(adventure: adventure, roster: roster) { id in
                        select(id)
                        dismiss()
                    }
                } else {
                    adventureList
                }
            }
            .navigationTitle(adventure?.title ?? "Who Can Play…?")
            .toolbar { toolbar }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }

    private var adventureList: some View {
        let matches = catalog.search(query)
        // A plain field rather than .searchable, which shows no field in a sheet on the Mac.
        return VStack(spacing: 0) {
            TextField("Code or title, such as 6-04 or Quest 14", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding()
            List(matches) { entry in
                Button { adventure = entry } label: { AdventureEntryRow(entry: entry) }
                    .buttonStyle(.plain)
            }
            .overlay {
                if matches.isEmpty { ContentUnavailableView.search(text: query) }
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        // A sheet on the Mac shows only these two placements, at its foot.
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
        }
        if adventure != nil {
            ToolbarItem(placement: .cancellationAction) {
                Button("Other Adventures") { adventure = nil }
            }
        }
    }
}

/// An adventure's code, title, campaign and levels.
struct AdventureEntryRow: View {
    let entry: AdventureEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.title)
            Text(details).font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var details: String {
        let levels = entry.levelRange?.displayText ?? "Levels unknown"
        return [entry.campaign.shortName, entry.kind.displayName, levels].joined(separator: " · ")
    }
}

/// The characters who can play the adventure first, then the rest, dimmed, with the reason they can't.
struct CandidateList: View {
    let adventure: AdventureEntry
    let roster: CharacterRoster
    let open: (CharacterRecord.ID) -> Void

    var body: some View {
        let candidates = AdventureFinder.candidates(for: adventure, in: roster)
        List {
            Section("Can Play") {
                rows(candidates.filter(\.eligibility.isEligible))
            }
            Section("Can't Play") {
                rows(candidates.filter { !$0.eligibility.isEligible })
            }
        }
    }

    private func rows(_ candidates: [Candidate]) -> some View {
        ForEach(candidates) { candidate in
            Button { open(candidate.id) } label: {
                HStack {
                    CharacterRow(record: candidate.character)
                    Spacer()
                    Text(EligibilityText.of(candidate.eligibility)).font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(candidate.eligibility.isEligible ? 1 : 0.55)
        }
    }
}

/// Why a character can or can't play: "played Apr 25, 2025", "level 9, range 1–4".
enum EligibilityText {
    static func of(_ eligibility: Eligibility) -> String {
        switch eligibility {
        case .eligible: ""
        case .alreadyPlayed(let date):
            date.map { "played \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "already played"
        case .outsideLevels(let level, let range): "level \(level), range \(range.displayText)"
        }
    }
}
