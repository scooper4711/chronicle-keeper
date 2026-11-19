import ChronicleKeeperKit
import SwiftUI

/// "Who can play…?": search every published adventure, pick one, see which characters haven't played it and are
/// inside its levels.
struct AdventureFinderView: View {
    let store: CharacterStore
    let search: any AdventureSearching
    let select: (CharacterRecord.ID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var question = Question()
    @State private var adventure: AdventureEntry?
    @State private var catalog: AdventureCatalog
    @State private var found = AdventureSearchResults.none
    @State private var isSearching = false
    @State private var failure = ""

    /// What the player is asking for; a change starts a new search.
    private struct Question: Hashable {
        var text = ""
        var campaign: Campaign?
    }

    private var roster: CharacterRoster { store.roster }

    // The account, where to search and what to do with the answer: three things the finder can't do without.
    init(store: CharacterStore, search: any AdventureSearching, select: @escaping (CharacterRecord.ID) -> Void) {
        self.store = store
        self.search = search
        self.select = select
        _catalog = State(initialValue: AdventureCatalog(roster: store.roster, covers: store.covers))
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
        .task(id: question) { await lookUp() }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }

    private var adventureList: some View {
        let matches = matches
        return VStack(spacing: 0) {
            filters
            List(matches) { entry in
                Button { adventure = entry } label: { AdventureEntryRow(entry: entry) }
                    .buttonStyle(.plain)
            }
            .overlay {
                if matches.isEmpty, isSearching {
                    ProgressView()
                } else if matches.isEmpty {
                    ContentUnavailableView.search(text: question.text)
                }
            }
        }
    }

    /// The player's own adventures that match, with the published ones the search found.
    private var matches: [AdventureEntry] {
        let published = found.adventures.filter { question.campaign == nil || $0.campaign == question.campaign }
        return AdventureCatalog.merged(
            published: published, own: catalog.search(question.text, campaign: question.campaign))
    }

    /// The search field, and the campaigns to narrow the list to when the player has characters in several.
    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // A plain field rather than .searchable, which shows no field in a sheet on the Mac.
                TextField("Code or title, such as 6-04 or Carnival", text: $question.text)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                if isSearching { ProgressView().controlSize(.small) }
            }
            if roster.campaigns.count > 1 {
                Picker("Campaign", selection: $question.campaign) {
                    Text("All").tag(Campaign?.none)
                    ForEach(roster.campaigns, id: \.self) { Text($0.shortName).tag(Campaign?.some($0)) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if !note.isEmpty {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    /// What the list holds, when that isn't simply every match.
    private var note: String {
        if !failure.isEmpty { return failure }
        if !found.isComplete {
            return "Warhorn has more matches than these. Type more of the code or title to narrow them down."
        }
        if question.text.trimmingCharacters(in: .whitespaces).isEmpty {
            return "These are the adventures in your sessions. Type a code or title to search every published "
                + "adventure on Warhorn."
        }
        return ""
    }

    /// Waits for a pause in the typing, then asks for the published adventures. A newer question cancels this one.
    private func lookUp() async {
        let campaigns = question.campaign.map { [$0] } ?? roster.campaigns
        do {
            try await Task.sleep(for: .milliseconds(350))
            isSearching = true
            let results = try await search.adventures(matching: question.text, in: campaigns)
            (found, failure) = (results, "")
        } catch {
            // A canceled search leaves the answer to the one that replaced it.
            if Task.isCancelled { return }
            (found, failure) = (.none, AdventureSearchFailure.text(for: error))
        }
        isSearching = false
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

extension AccountSession {
    /// Where "Who can play…?" looks up the published adventures: Warhorn, or the demo's own made-up few.
    var adventureSearch: any AdventureSearching {
        isDemo ? DemoAdventureSearch() : WarhornCatalog.forApp
    }
}

extension WarhornCatalog {
    /// One connection for the whole run, apart from the one that carries the paizo.com sign-in.
    static let forApp = WarhornCatalog(http: URLSessionHTTPClient())
}
