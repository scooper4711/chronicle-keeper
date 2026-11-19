import Foundation
import Observation

/// Which account the app shows: the user's own (signed in or not), or the fictional demo account.
@MainActor
@Observable
public final class AccountSession {
    public enum Mode: Equatable, Sendable {
        case signedOut
        case signedIn(email: String)
        case demo
    }

    public private(set) var mode: Mode
    public private(set) var store: CharacterStore
    public private(set) var signInError: String?
    public private(set) var isSigningIn = false

    private let live: LiveAccount
    /// The user's own account's store, kept for the whole run so syncing always has it, even during the demo.
    public let liveStore: CharacterStore
    /// Syncing of the user's data between their devices; nil when the build or iCloud doesn't allow it.
    public private(set) var sync: SettingsSync?

    /// The parts that reach paizo.com and the user's files.
    public struct LiveAccount: Sendable {
        public let client: OrganizedPlayClient
        public let credentials: CredentialStore
        public let repository: CharacterRepository

        public init(client: OrganizedPlayClient, credentials: CredentialStore, repository: CharacterRepository) {
            self.client = client
            self.credentials = credentials
            self.repository = repository
        }
    }

    public init(live: LiveAccount) {
        self.live = live
        mode = live.credentials.load().map { .signedIn(email: $0.email) } ?? .signedOut
        let client = live.client
        liveStore = CharacterStore(repository: live.repository) { try await client.fetchAccount() }
        store = liveStore
        store.load()
    }

    public var isDemo: Bool { mode == .demo }

    /// Starts syncing the user's data through iCloud, when the build and the device allow it.
    public func startSync(portraits: PortraitStore) async {
        guard sync == nil, let folder = live.repository.folder else { return }
        sync = await SettingsSync.start(store: liveStore, portraits: portraits, folder: folder)
    }
    /// Starts keeping boon PDFs: in iCloud Drive when the build has it, otherwise beside the app's files.
    public func startBoons() async {
        guard liveStore.boonDownloads == nil else { return }
        let local = live.repository.folder ?? FileManager.default.temporaryDirectory
        let library = await BoonLibrary.standard(localFolder: local)
        await liveStore.useBoonDownloads(BoonDownloads(library: library, source: live.client))
    }

    /// Starts keeping chronicle PDFs: in iCloud Drive when the build has it, otherwise beside the app's files.
    public func startChronicles() async {
        guard liveStore.chronicleLibrary == nil else { return }
        let local = live.repository.folder ?? FileManager.default.temporaryDirectory
        let library = await ChronicleLibrary.standard(localFolder: local)
        liveStore.useChronicleLibrary(library)
    }

    /// Starts looking up the covers of the adventures in the user's sessions, in the catalog given.
    public func startCovers(search: any AdventureSearching) async {
        await liveStore.useCoverFinder(CoverFinder(search: search))
    }

    public var canRefresh: Bool { mode != .signedOut && !store.isRefreshing }

    /// Signs in with new credentials, then reads the account.
    public func signIn(_ account: Credentials) async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            try await live.client.signIn(account)
            signInError = nil
            show(.signedIn(email: account.email), store: liveStore)
            await store.refresh()
        } catch {
            signInError = FailureMessage.text(for: error)
        }
    }

    /// Forgets the password and the site data. The user's own settings stay.
    public func signOut() {
        do { try live.credentials.delete() } catch { signInError = error.localizedDescription }
        liveStore.signOut()
        store = liveStore
        mode = .signedOut
    }

    public func startDemo() {
        let demo = CharacterStore(repository: InMemoryCharacterRepository()) {
            DemoAccount.snapshot(fetchedAt: Date())
        }
        show(.demo, store: demo)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Demo Boons", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        let downloads = BoonDownloads(library: BoonLibrary(folder: folder), source: DemoBoons.Source())
        let chronicleFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Demo Chronicles", isDirectory: true)
        try? FileManager.default.removeItem(at: chronicleFolder)
        Task {
            await demo.refresh()
            await demo.useBoonDownloads(downloads)
            let chronicles = ChronicleLibrary(folder: chronicleFolder)
            demo.attempt { try DemoChronicles.addSheet(to: chronicles) }
            demo.useChronicleLibrary(chronicles)
        }
    }

    public func leaveDemo() {
        guard isDemo else { return }
        let email = live.credentials.load()?.email
        show(email.map { .signedIn(email: $0) } ?? .signedOut, store: liveStore)
    }

    private func show(_ newMode: Mode, store newStore: CharacterStore) {
        mode = newMode
        store = newStore
        store.load()
    }
}
