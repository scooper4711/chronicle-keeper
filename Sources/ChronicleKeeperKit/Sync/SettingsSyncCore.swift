import CloudKit
import Foundation

/// What syncing remembers between launches, kept in `sync-state.json` beside the user's settings.
public struct SyncLedger: Codable, Sendable {
    /// The engine's own state; nil before the first start, which then uploads everything.
    public var engineState: CKSyncEngine.State.Serialization?
    /// Per character number: the server's last copy (its system fields) and the settings both sides agreed on.
    public var entries: [String: Entry] = [:]

    public struct Entry: Codable, Sendable, Equatable {
        public var systemFields: Data?
        /// The agreed settings. Their ledger isn't encoded with them (see `CharacterSettings.wealth`), so it is
        /// kept in `ancestorWealth` too; read both through `agreed`.
        public var ancestor: CharacterSettings
        /// The agreed ledger; nil in a file written before the ledger existed.
        public var ancestorWealth: CharacterWealth?

        public init(systemFields: Data?, ancestor: CharacterSettings) {
            self.systemFields = systemFields
            self.ancestor = ancestor
            ancestorWealth = ancestor.wealth
        }

        /// The settings both sides agreed on, with their ledger.
        public var agreed: CharacterSettings {
            var settings = ancestor
            settings.wealth = ancestorWealth ?? CharacterWealth()
            return settings
        }
    }

    public init() {}
}

/// iCloud refused to keep a character's settings, for a reason that trying again won't fix.
public struct SettingsSyncError: Error, Equatable, LocalizedError {
    public let failure: String

    public var errorDescription: String? { "Syncing with iCloud failed: \(failure)" }
}

/// Syncing's decisions, without CloudKit's engine, so tests reach them: how a record from the server is merged in,
/// what a save leaves behind, and which record goes up.
public struct SettingsSyncCore: Sendable {
    public private(set) var ledger: SyncLedger

    public init(ledger: SyncLedger = SyncLedger()) {
        self.ledger = ledger
    }

    /// The outcome of merging a server record: the settings to keep here, and whether they must go back up.
    public struct Merged: Equatable, Sendable {
        public let settings: CharacterSettings
        public let needsUpload: Bool
    }

    /// Merges a record another device saved, or the server's copy after a conflict, into `local`.
    public mutating func received(_ record: CKRecord, local: CharacterSettings?) -> Merged? {
        guard let content = SettingsRecord.content(of: record) else { return nil }
        let ancestor = ledger.entries[content.number]?.agreed ?? CharacterSettings()
        var remote = content.settings
        // A record saved only by an older build has no ledger: that says nothing about the ledger, so it is taken
        // as unchanged rather than as deleted.
        if !content.hasWealth { remote.wealth = ancestor.wealth }
        let merged = SettingsMerge.merge(local: local ?? ancestor, remote: remote, ancestor: ancestor)
        ledger.entries[content.number] = SyncLedger.Entry(systemFields: record.archivedSystemFields, ancestor: remote)
        return Merged(settings: merged, needsUpload: merged != content.settings)
    }

    /// The server took a save: its copy is now what both sides agree on.
    public mutating func saved(_ record: CKRecord) {
        guard let content = SettingsRecord.content(of: record) else { return }
        ledger.entries[content.number] = SyncLedger.Entry(
            systemFields: record.archivedSystemFields, ancestor: content.settings)
    }

    /// The record to save for a character, over the server's last copy when there is one.
    public func record(for number: String, settings: CharacterSettings, portraitFile: URL?) throws -> CKRecord {
        let record = ledger.entries[number]?.systemFields.flatMap(CKRecord.fromSystemFields)
            ?? CKRecord(recordType: SettingsRecord.recordType, recordID: SettingsRecord.recordID(for: number))
        try SettingsRecord.fill(record, with: settings, portraitFile: portraitFile)
        return record
    }

    /// The characters whose settings the server hasn't taken, such as edits a rejected save left behind. Settings
    /// that were never changed have nothing to send.
    public func unsynced(in settings: [String: CharacterSettings]) -> [String] {
        settings.compactMap { number, value in
            let agreed = ledger.entries[number]?.agreed ?? CharacterSettings()
            return value == agreed ? nil : number
        }
    }

    /// Whether the engine will send a failed save again by itself.
    public static func isTemporary(_ code: CKError.Code) -> Bool {
        let temporary: Set<CKError.Code> = [
            .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy,
            .accountTemporarilyUnavailable, .notAuthenticated, .batchRequestFailed, .operationCancelled
        ]
        return temporary.contains(code)
    }

    /// The server doesn't hold the record (any more): the next save makes a new one.
    public mutating func forgetServerCopy(of number: String) {
        ledger.entries[number]?.systemFields = nil
    }

    /// Another iCloud account, or the user deleted the app's iCloud data: nothing the server held is known now.
    /// The settings here stay, and go up again in full.
    public mutating func forgetServer() {
        ledger = SyncLedger()
    }

    public mutating func setEngineState(_ state: CKSyncEngine.State.Serialization) {
        ledger.engineState = state
    }
}
