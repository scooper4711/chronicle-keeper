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
    /// Each session's chronicle PDF that is in the chronicle library, keyed by the session's own ID.
    public private(set) var chronicleFiles: [String: URL] = [:]
    /// Where chronicle PDFs are kept; nil until the app has looked up iCloud.
    public private(set) var chronicleLibrary: ChronicleLibrary?

    /// Looks covers up; nil for an account that has none to find, such as the demo.
    private var coverFinder: CoverFinder?
    /// The cover pass under way, which signing out stops.
    private(set) var coverPass: Task<Void, Never>?

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
        locateChronicleFiles()
    }

    /// Reads the account again, then starts looking up the covers of any adventures that are new, without waiting
    /// for them: a first pass over a long history takes a while, and signing in shouldn't. The saved data stays as
    /// it was when reading fails.
    public func refresh() async {
        await readAccount()
        startCoverPass()
    }

    private func readAccount() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            var fresh = try await fetchAccount()
            fresh.covers = snapshot?.covers ?? [:]
            try repository.saveSnapshot(fresh)
            snapshot = fresh
            lastRefresh = fresh.fetchedAt
            errorMessage = nil
            rebuild()
            locateChronicleFiles()
        } catch {
            errorMessage = FailureMessage.text(for: error)
            return
        }
        await downloadMissingBoons()
    }

    /// Starts looking covers up, beginning with the adventures of the account that is already saved, and waits for
    /// that pass.
    public func useCoverFinder(_ finder: CoverFinder) async {
        coverFinder = finder
        startCoverPass()
        await waitForCovers()
    }

    /// Waits for the cover pass under way, if there is one.
    func waitForCovers() async {
        await coverPass?.value
    }

    /// Where the cover of a session's adventure is, once it has been looked up.
    public func cover(of session: PlayedSession) -> URL? {
        snapshot?.covers[session.adventureEntry.id]
    }

    /// The covers saved with the account, by adventure.
    public var covers: [String: URL] { snapshot?.covers ?? [:] }

    /// Looks up the cover of each adventure in the sessions that has none yet and saves them with the account, so
    /// that showing one later asks nobody. A numbered adventure the catalog doesn't have is asked for again next time.
    /// One pass runs at a time; adventures that are new while it runs wait for the next refresh.
    private func startCoverPass() {
        guard let finder = coverFinder, coverPass == nil else { return }
        let adventures = Array(adventuresWithoutCover().prefix(Self.coversPerPass))
        guard !adventures.isEmpty else { return }
        coverPass = Task {
            keep(await finder.covers(of: adventures))
        }
    }

    /// Adds the covers a pass found to the account as it is now, which loading it again during the pass may have
    /// replaced, and saves them. A pass that signing out canceled keeps nothing.
    private func keep(_ found: [String: URL]) {
        guard !Task.isCancelled else { return }
        coverPass = nil
        guard !found.isEmpty, var current = snapshot else { return }
        current.covers.merge(found) { _, new in new }
        snapshot = current
        attempt { try repository.saveSnapshot(current) }
    }

    /// The adventures one pass asks for at most, so that a long history doesn't use up the requests the catalog
    /// allows an address in a few minutes; the rest follow on later refreshes.
    static let coversPerPass = 100

    private func adventuresWithoutCover() -> [AdventureEntry] {
        var known = Set(covers.keys)
        return (snapshot?.sessions ?? []).map(\.adventureEntry).filter { known.insert($0.id).inserted }
    }

    /// Starts keeping chronicle PDFs, and finds the ones already in the library.
    public func useChronicleLibrary(_ library: ChronicleLibrary) {
        chronicleLibrary = library
        locateChronicleFiles()
    }

    /// Attaches a PDF to one session as its chronicle sheet, replacing any it already had.
    public func attachChronicle(_ data: Data, to session: PlayedSession, characterNumber: String) {
        guard let library = chronicleLibrary else { return }
        let url = library.fileURL(characterNumber: characterNumber, session: session)
        // This call's own outcome: an error left from an earlier failure mustn't stop the sheet showing.
        guard attempt({ try library.save(data, to: url) }) != nil else { return }
        // A sheet 1.0.0 filed by name, that it replaces.
        if let replaced = chronicleFiles[session.id], replaced != url { attempt { try library.remove(at: replaced) } }
        chronicleFiles[session.id] = url
    }

    /// Removes a session's chronicle PDF.
    public func removeChronicle(from session: PlayedSession, characterNumber: String) {
        guard let library = chronicleLibrary else { return }
        let url = chronicleFiles[session.id] ?? library.fileURL(characterNumber: characterNumber, session: session)
        guard attempt({ try library.remove(at: url) }) != nil else { return }
        chronicleFiles[session.id] = nil
    }

    /// Finds each session's sheet, moving any that 1.0.0 filed by the character's name to where it goes now.
    private func locateChronicleFiles() {
        guard let library = chronicleLibrary else { return }
        let namedFiles = library.namedFiles()
        var files: [String: URL] = [:]
        for record in roster.characters {
            for session in record.sessions.map(\.session) {
                let url = library.fileURL(characterNumber: record.id, session: session)
                if library.hasFile(at: url) {
                    files[session.id] = url
                } else if let named = namedFiles[session.keyWithinCharacter] {
                    files[session.id] = library.moveNamedFile(named, to: url)
                }
            }
        }
        chronicleFiles = files
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
        coverPass?.cancel()
        coverPass = nil
        do { try repository.deleteSnapshot() } catch { errorMessage = error.localizedDescription }
        snapshot = nil
        lastRefresh = nil
        boonFiles = [:]
        unavailableBoons = []
        chronicleFiles = [:]
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

    /// Shows a failure that happened away from any call to `attempt`.
    public func reportFailure(_ error: any Error) {
        errorMessage = error.localizedDescription
    }

    private func rebuild() {
        var roster = CharacterRoster(
            summaries: snapshot?.characters ?? [], sessions: snapshot?.sessions ?? [], settings: settings)
        roster.attach(snapshot?.boons ?? [])
        self.roster = roster
    }
}
