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
        }
    }

    /// Forgets the site data (the user's settings stay).
    public func signOut() {
        do { try repository.deleteSnapshot() } catch { errorMessage = error.localizedDescription }
        snapshot = nil
        lastRefresh = nil
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
        roster = CharacterRoster(
            summaries: snapshot?.characters ?? [], sessions: snapshot?.sessions ?? [], settings: settings)
    }
}
