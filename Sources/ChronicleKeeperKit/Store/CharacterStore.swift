import Foundation
import Observation

/// What the app shows: the roster, built from the saved site data and the user's settings.
@MainActor
@Observable
public final class CharacterStore {
    public private(set) var roster = CharacterRoster(summaries: [], sessions: [])
    public private(set) var lastRefresh: Date?
    public private(set) var isRefreshing = false
    public internal(set) var errorMessage: String?
    /// Each boon's PDF that is in the boon library.
    public internal(set) var boonFiles: [Boon.ID: URL] = [:]
    /// Boons paizo.com wouldn't hand over as a PDF yet.
    public internal(set) var unavailableBoons: Set<Boon.ID> = []
    public internal(set) var isDownloadingBoons = false
    /// Where boon PDFs are kept and where they come from; nil until the app has looked up iCloud.
    public internal(set) var boonDownloads: BoonDownloads?
    /// Each session's chronicle PDF that is in the chronicle library, keyed by the session's own ID.
    public private(set) var chronicleFiles: [String: URL] = [:]
    /// Where chronicle PDFs are kept; nil until the app has looked up iCloud.
    public private(set) var chronicleLibrary: ChronicleLibrary?
    /// Reads chronicle sheets (R1.10); tests give it a stand-in for text recognition.
    public var sheetReader = SheetReader()

    /// What each character may claim of the free rewards, by character number (see `CharacterStore+Rewards`).
    public internal(set) var claimableRewards: [String: [ClaimableReward]] = [:]
    var rewardSource: RewardCatalogSource?
    var rewardCatalog: RewardCatalog?
    var rewardEligibility: RewardEligibility?
    var rewardFetch: Task<Void, Never>?

    /// Looks covers up; nil for an account that has none to find, such as the demo.
    private var coverFinder: CoverFinder?
    /// The cover pass under way, which signing out stops.
    private(set) var coverPass: Task<Void, Never>?

    let repository: CharacterRepository
    private let fetchAccount: @Sendable () async throws -> AccountSnapshot
    var snapshot: AccountSnapshot?
    private var settings: [String: CharacterSettings] = [:]
    /// Why the user's settings couldn't be read, or nil when they were (see `loadSettings`).
    private var unreadableSettings: String?

    /// Whether the user's settings were read, so changes to them can be saved and synced.
    public var canSaveSettings: Bool { unreadableSettings == nil }

    private var unsavedMessage: String {
        "\(unreadableSettings ?? "") Changes to notes, corrections and the ledger aren't saved until it can be read."
    }
    /// Told the character number of each change the user makes, for syncing to send it.
    public var onLocalChange: @MainActor (String) -> Void = { _ in }

    public init(repository: CharacterRepository, fetchAccount: @escaping @Sendable () async throws -> AccountSnapshot) {
        self.repository = repository
        self.fetchAccount = fetchAccount
    }

    /// Shows what was saved last time, without touching the network.
    public func load() {
        errorMessage = nil
        loadSnapshot()
        loadSettings()
        rebuild()
        locateChronicleFiles()
        loadRewardCatalog()
    }

    private func loadSnapshot() {
        do {
            snapshot = try repository.loadSnapshot()
            lastRefresh = snapshot?.fetchedAt
            locateBoonFiles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reads the user's settings. When they can't be read, nothing is saved or synced until they can: saving the
    /// little that was read would overwrite the files, and syncing would spread the loss.
    private func loadSettings() {
        do {
            settings = try repository.loadSettings()
            unreadableSettings = nil
        } catch {
            unreadableSettings = error.localizedDescription
            errorMessage = unsavedMessage
        }
    }

    /// Reads the account again, then starts looking up the covers of any adventures that are new, without waiting
    /// for them: a first pass over a long history takes a while, and signing in shouldn't. The saved data stays as
    /// it was when reading fails.
    public func refresh() async {
        await readAccount()
        startCoverPass()
        startRewardFetch()
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
            findClaimableRewards()
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

    /// Attaches a PDF to one session as its chronicle sheet, replacing any it already had. False when it couldn't
    /// be saved, which shows as an error.
    @discardableResult
    public func attachChronicle(_ data: Data, to session: PlayedSession, characterNumber: String) -> Bool {
        guard let library = chronicleLibrary else { return false }
        let url = library.fileURL(characterNumber: characterNumber, session: session)
        // This call's own outcome: an error left from an earlier failure mustn't stop the sheet showing.
        guard attempt({ try library.save(data, to: url) }) != nil else { return false }
        // A sheet 1.0.0 filed by name, that it replaces.
        if let replaced = chronicleFiles[session.id], replaced != url { attempt { try library.remove(at: replaced) } }
        chronicleFiles[session.id] = url
        return true
    }

    /// Removes a session's chronicle PDF, and what was read from it.
    public func removeChronicle(from session: PlayedSession, characterNumber: String) {
        guard let library = chronicleLibrary else { return }
        let url = chronicleFiles[session.id] ?? library.fileURL(characterNumber: characterNumber, session: session)
        guard attempt({ try library.remove(at: url) }) != nil else { return }
        chronicleFiles[session.id] = nil
        forgetReading(of: session, characterNumber: characterNumber)
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

    /// Forgets the site data (the user's settings stay).
    public func signOut() {
        coverPass?.cancel()
        coverPass = nil
        stopRewardFetch()
        do { try repository.deleteSnapshot() } catch { errorMessage = error.localizedDescription }
        snapshot = nil
        lastRefresh = nil
        boonFiles = [:]
        unavailableBoons = []
        chronicleFiles = [:]
        rebuild()
        findClaimableRewards()
    }

    public func settings(for number: String) -> CharacterSettings {
        settings[number] ?? CharacterSettings()
    }

    /// Changes one character's settings and saves them.
    public func update(_ number: String, _ change: (inout CharacterSettings) -> Void) {
        guard unreadableSettings == nil else {
            errorMessage = unsavedMessage
            return
        }
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
        guard !changes.isEmpty, unreadableSettings == nil else { return }
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
