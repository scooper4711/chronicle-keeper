import ChronicleKeeperKit
import SwiftUI

/// The sign-in screen until there is an account to show, then campaigns and characters beside the selected one.
struct MainWindow: View {
    @Environment(AccountSession.self) private var session

    var body: some View {
        if session.mode == .signedOut {
            SignInView()
        } else {
            CharacterBrowser(store: session.store)
                .id(ObjectIdentifier(session.store))
        }
    }
}

/// The split view for one account's characters.
struct CharacterBrowser: View {
    let store: CharacterStore
    @Environment(AccountSession.self) private var session
    @State private var selection: CharacterRecord.ID?
    @State private var showsFinder = false

    var body: some View {
        NavigationSplitView {
            CharacterSidebar(roster: store.roster, selection: $selection)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            #if os(iOS)
                // On the iPhone only the sidebar's own toolbar shows while it is on screen.
                .toolbar { toolbar }
                .toolbar { ToolbarItem(placement: .topBarLeading) { AccountMenu() } }
            #endif
        } detail: {
            detail
        }
        #if os(macOS)
        .toolbar { toolbar }
        #endif
        .sheet(isPresented: $showsFinder) {
            AdventureFinderView(store: store, search: session.adventureSearch) { selection = $0 }
        }
        .focusedSceneValue(\.showsFinder, $showsFinder)
        .safeAreaInset(edge: .bottom) { StatusBar(store: store, isDemo: session.isDemo) }
        .task { await refreshIfNeverRead() }
    }

    @ViewBuilder private var detail: some View {
        if let record = store.roster.characters.first(where: { $0.id == selection }) {
            // A stack, so an adventure opens its session's details over the character; another character starts
            // again at its own overview.
            NavigationStack {
                CharacterDetailView(record: record, store: store)
            }
            .id(record.id)
        } else {
            ContentUnavailableView(
                "No Character Selected", systemImage: "person.crop.rectangle.stack",
                description: Text(store.roster.characters.isEmpty
                    ? "Refresh to read your characters from paizo.com." : "Pick a character in the sidebar."))
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { showsFinder = true } label: { Label("Who Can Play…", systemImage: "person.2.badge.gearshape") }
                .help("Find the characters who can still play an adventure")
            Button { Task { await store.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .help("Read your characters and sessions from paizo.com again")
                .disabled(!session.canRefresh)
        }
    }

    private func refreshIfNeverRead() async {
        guard store.lastRefresh == nil, session.canRefresh else { return }
        await store.refresh()
    }
}

/// The last refresh, a refresh in progress, or what went wrong.
struct StatusBar: View {
    let store: CharacterStore
    let isDemo: Bool
    @Environment(AccountSession.self) private var session

    var body: some View {
        HStack(spacing: 8) {
            if store.isRefreshing {
                ProgressView().controlSize(.small)
                Text("Reading paizo.com…")
            } else if let error = store.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                // Never cut short: a site-change message ends with where to find an update.
                Text(error)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else if let date = store.lastRefresh {
                Text("Read \(date, format: .relative(presentation: .named))")
            }
            Spacer()
            if isDemo {
                Text("Demo account").foregroundStyle(.secondary)
                Button("Leave the Demo") { session.leaveDemo() }
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
