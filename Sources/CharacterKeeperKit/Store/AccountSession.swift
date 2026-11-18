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
        store = Self.liveStore(live)
        store.load()
    }

    public var isDemo: Bool { mode == .demo }
    public var canRefresh: Bool { mode != .signedOut && !store.isRefreshing }

    /// Signs in with new credentials, then reads the account.
    public func signIn(_ account: Credentials) async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            try await live.client.signIn(account)
            signInError = nil
            show(.signedIn(email: account.email), store: Self.liveStore(live))
            await store.refresh()
        } catch {
            signInError = error.localizedDescription
        }
    }

    /// Forgets the password and the site data. The user's own settings stay.
    public func signOut() {
        do { try live.credentials.delete() } catch { signInError = error.localizedDescription }
        store.signOut()
        mode = .signedOut
    }

    public func startDemo() {
        let demo = CharacterStore(repository: InMemoryCharacterRepository()) { DemoAccount.snapshot() }
        show(.demo, store: demo)
        Task { await demo.refresh() }
    }

    public func leaveDemo() {
        guard isDemo else { return }
        let email = live.credentials.load()?.email
        show(email.map { .signedIn(email: $0) } ?? .signedOut, store: Self.liveStore(live))
    }

    private func show(_ newMode: Mode, store newStore: CharacterStore) {
        mode = newMode
        store = newStore
        store.load()
    }

    private static func liveStore(_ live: LiveAccount) -> CharacterStore {
        let client = live.client
        return CharacterStore(repository: live.repository) { try await client.fetchAccount() }
    }
}
