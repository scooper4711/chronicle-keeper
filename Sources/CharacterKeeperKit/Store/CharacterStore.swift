import Foundation
import Observation

/// What the app shows: the roster, built from the saved site data and the user's settings.
@MainActor
@Observable
public final class CharacterStore {
    public private(set) var roster = CharacterRoster(summaries: [], sessions: [])
    public private(set) var lastRefresh: Date?
    public private(set) var isRefreshing = false
    public private(set) var errorMessage: String?
    /// Each boon's PDF that is in the boon library.
    public private(set) var boonFiles: [Boon.ID: URL] = [:]
    /// Boons paizo.com wouldn't hand over as a PDF yet.
    public private(set) var unavailableBoons: Set<Boon.ID> = []
    public private(set) var isDownloadingBoons = false
    /// Where boon PDFs are kept and where they come from; nil until the app has looked up iCloud.
    public private(set) var boonDownloads: BoonDownloads?

    private let repository: CharacterRepository
    private let fetchAccount: @Sendable () async throws -> AccountSnapshot
    private var snapshot: AccountSnapshot?
    private var settings: [String: CharacterSettings] = [:]
    /// Told the character number of each change the user makes, for syncing to send it.
    public var onLocalChange: @MainActor (String) -> Void = { _ in }

    public init(repository: CharacterRepository, fetchAccount: @escaping @Sendable () async throws -> AccountSnapshot) {
        self.repository = repository
        self.fetchAccount = fetchAccount
    }

    /// Shows what was saved last time, without touching the network.
    public func load() {
        do {
            snapshot = try repository.loadSnapshot()
            settings = try repository.loadSettings()
            lastRefresh = snapshot?.fetchedAt
            errorMessage = nil
            locateBoonFiles()
        } catch {
            errorMessage = error.localizedDescription
        }
        rebuild()
    }

    /// Reads the account again. The saved data stays as it was when this fails.
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let fresh = try await fetchAccount()
            try repository.saveSnapshot(fresh)
            snapshot = fresh
            lastRefresh = fresh.fetchedAt
            errorMessage = nil
            rebuild()
        } catch {
            errorMessage = FailureMessage.text(for: error)
            return
        }
        await downloadMissingBoons()
    }

    /// Starts keeping boon PDFs, and finds the ones already in the library.
    public func useBoonDownloads(_ downloads: BoonDownloads) async {
        boonDownloads = downloads
        locateBoonFiles()
        if lastRefresh != nil { await downloadMissingBoons() }
    }

    /// Downloads each boon whose PDF isn't in the library yet: one another device already saved to iCloud Drive
    /// counts as there.
    public func downloadMissingBoons() async {
        guard let downloads = boonDownloads, !isDownloadingBoons else { return }
        isDownloadingBoons = true
        defer { isDownloadingBoons = false }
        let boons = snapshot?.boons ?? []
        for (boon, url) in missingBoons(boons, in: downloads.library) {
            do {
                try await download(boon, to: url, with: downloads)
            } catch {
                errorMessage = FailureMessage.text(for: error)
                return
            }
        }
    }

    private func download(_ boon: Boon, to url: URL, with downloads: BoonDownloads) async throws {
        guard let data = try await downloads.source.pdf(for: boon) else {
            unavailableBoons.insert(boon.id)
            return
        }
        try downloads.library.save(data, to: url)
        boonFiles[boon.id] = url
        unavailableBoons.remove(boon.id)
    }

    private func missingBoons(_ boons: [Boon], in library: BoonLibrary) -> [(Boon, URL)] {
        locateBoonFiles()
        let urls = library.fileURLs(for: boons)
        return boons.compactMap { boon in
            guard boonFiles[boon.id] == nil, let url = urls[boon.id] else { return nil }
            return (boon, url)
        }
    }

    private func locateBoonFiles() {
        guard let library = boonDownloads?.library else { return }
        boonFiles = library.fileURLs(for: snapshot?.boons ?? []).filter { library.hasFile(at: $0.value) }
    }

    /// Forgets the site data (the user's settings stay).
    public func signOut() {
        do { try repository.deleteSnapshot() } catch { errorMessage = error.localizedDescription }
        snapshot = nil
        lastRefresh = nil
        boonFiles = [:]
        unavailableBoons = []
        rebuild()
    }

    public func settings(for number: String) -> CharacterSettings {
        settings[number] ?? CharacterSettings()
    }

    /// Changes one character's settings and saves them.
    public func update(_ number: String, _ change: (inout CharacterSettings) -> Void) {
        var changed = settings(for: number)
        change(&changed)
        settings[number] = changed
        saveSettings()
        onLocalChange(number)
    }

    /// Every character's settings, as syncing sends them.
    public var allSettings: [String: CharacterSettings] { settings }

    /// Takes settings merged from another device. Unlike `update`, this isn't reported as a local change.
    public func applyRemote(_ changes: [String: CharacterSettings]) {
        guard !changes.isEmpty else { return }
        settings.merge(changes) { _, remote in remote }
        saveSettings()
    }

    private func saveSettings() {
        do {
            try repository.saveSettings(settings)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        rebuild()
    }

    /// Runs work that may fail, showing its error the way a failed refresh shows; nil when it failed.
    public func attempt<Value>(_ work: () throws -> Value) -> Value? {
        do {
            return try work()
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func rebuild() {
        var roster = CharacterRoster(
            summaries: snapshot?.characters ?? [], sessions: snapshot?.sessions ?? [], settings: settings)
        roster.attach(snapshot?.boons ?? [])
        self.roster = roster
    }
}

/// The boon library and where its PDFs come from.
public struct BoonDownloads: Sendable {
    public let library: BoonLibrary
    public let source: BoonSource

    public init(library: BoonLibrary, source: BoonSource) {
        self.library = library
        self.source = source
    }
}
