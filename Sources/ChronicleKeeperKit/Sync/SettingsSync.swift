import CloudKit
import Foundation

/// Syncs the user's own data between their devices through CloudKit (plan, "iCloud sync"). The decisions are in
/// `SettingsSyncCore`; this hands records between it, the store and `CKSyncEngine`. Unit tests can't reach this: a
/// container without the entitlement stops the process.
public actor SettingsSync: CKSyncEngineDelegate {
    /// The `Info.plist` key that names the container, in builds signed with the iCloud entitlement only.
    public static let containerKey = "ChronicleKeeperContainer"

    private let store: CharacterStore
    private let portraits: PortraitStore
    private let ledgerFile: URL
    private var core: SettingsSyncCore
    private var engine: CKSyncEngine?
    /// Characters whose record on the server this build can't read, such as a ledger saved by a newer version.
    /// Sending this device's copy would overwrite it, so they aren't sent until the app is updated.
    private var unreadable: Set<String> = []

    init(store: CharacterStore, portraits: PortraitStore, ledgerFile: URL) {
        self.store = store
        self.portraits = portraits
        self.ledgerFile = ledgerFile
        core = SettingsSyncCore(ledger: Self.readLedger(from: ledgerFile))
    }

    /// Starts syncing `store`'s settings; nil when the build names no container or iCloud isn't available, and the
    /// app then keeps its data on this device only. No container is made before the name is checked, as one the
    /// build has no entitlement for stops the app.
    public static func start(store: CharacterStore, portraits: PortraitStore, folder: URL) async -> SettingsSync? {
        let name = Bundle.main.object(forInfoDictionaryKey: containerKey) as? String ?? ""
        guard !name.isEmpty else { return nil }
        let container = CKContainer(identifier: name)
        guard (try? await container.accountStatus()) == .available else { return nil }
        let sync = SettingsSync(
            store: store, portraits: portraits, ledgerFile: folder.appendingPathComponent("sync-state.json"))
        await sync.attach(to: container.privateCloudDatabase)
        await MainActor.run {
            store.onLocalChange = { number in Task { await sync.changed(number) } }
        }
        return sync
    }

    /// Queues a character's settings to go up.
    public func changed(_ number: String) {
        guard !unreadable.contains(number) else { return }
        engine?.state.add(pendingRecordZoneChanges: [.saveRecord(SettingsRecord.recordID(for: number))])
    }

    private func attach(to database: CKDatabase) async {
        let isFirstStart = core.ledger.engineState == nil
        let configuration = CKSyncEngine.Configuration(
            database: database, stateSerialization: core.ledger.engineState, delegate: self)
        engine = CKSyncEngine(configuration)
        if isFirstStart { await uploadEverything() } else { await uploadUnsynced() }
    }

    /// Sends what an earlier launch couldn't, as the engine forgets a save the server rejected.
    private func uploadUnsynced() async {
        let settings = await MainActor.run { store.allSettings }
        core.unsynced(in: settings).forEach(changed)
    }

    private func uploadEverything() async {
        let numbers = await MainActor.run { Array(store.allSettings.keys) }
        engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SettingsRecord.zoneID))])
        engine?.state.add(pendingRecordZoneChanges: numbers.map { .saveRecord(SettingsRecord.recordID(for: $0)) })
    }

    // MARK: - CKSyncEngineDelegate

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            core.setEngineState(update.stateSerialization)
            saveLedger()
        case .accountChange(let change):
            await accountChanged(change.changeType)
        case .fetchedDatabaseChanges(let changes):
            await zonesDeleted(changes.deletions.filter { $0.zoneID == SettingsRecord.zoneID })
        case .fetchedRecordZoneChanges(let changes):
            await merge(changes.modifications.map(\.record))
        case .sentRecordZoneChanges(let sent):
            sent.savedRecords.forEach { core.saved($0) }
            await settle(sent.failedRecordSaves)
            saveLedger()
        default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        let settings = await MainActor.run { store.allSettings }
        let records = pending.compactMap { change -> CKRecord? in
            guard case .saveRecord(let id) = change else { return nil }
            return record(for: id.recordName, settings: settings)
        }
        // A change whose character has no settings any more has nothing to send: drop it, or it stays pending.
        let sendable = Set(records.map(\.recordID))
        let dropped = pending.filter { change in
            if case .saveRecord(let id) = change { return !sendable.contains(id) }
            return false
        }
        syncEngine.state.remove(pendingRecordZoneChanges: dropped)
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.recordID, $0) })
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending.filter { !dropped.contains($0) }) {
            byID[$0]
        }
    }

    // MARK: - Events

    private func record(for number: String, settings: [String: CharacterSettings]) -> CKRecord? {
        guard let value = settings[number] else { return nil }
        let portrait = portraits.existingFile(named: value.portraitFileName)
        return try? core.record(for: number, settings: value, portraitFile: portrait)
    }

    /// Merges records other devices saved, keeps their portraits, and sends back what the merge changed.
    private func merge(_ records: [CKRecord]) async {
        // Merging into settings the store couldn't read would record changes the store then refuses.
        guard !records.isEmpty, await MainActor.run(body: { store.canSaveSettings }) else { return }
        let local = await MainActor.run { store.allSettings }
        var changes: [String: CharacterSettings] = [:]
        for record in records {
            guard let content = SettingsRecord.content(of: record) else {
                await holdBack(record)
                continue
            }
            guard let merged = core.received(record, local: local[content.number]) else { continue }
            keepPortrait(of: content, merged: merged.settings, previous: local[content.number])
            if merged.settings != local[content.number] { changes[content.number] = merged.settings }
            if merged.needsUpload { changed(content.number) }
        }
        saveLedger()
        let toApply = changes
        await MainActor.run { store.applyRemote(toApply) }
    }

    /// Stops sending a character whose server record this build can't read, and says so once. Without this, each
    /// save conflicts, can't be merged and is sent again, forever.
    private func holdBack(_ record: CKRecord) async {
        let number = record.recordID.recordName
        guard SettingsRecord.isCharacterRecord(record), unreadable.insert(number).inserted else { return }
        engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
        await report("A newer version of Chronicle Keeper on another device saved character \(number). Update "
            + "this device to sync that character again.")
    }

    private func keepPortrait(of content: SettingsRecord.Content, merged: CharacterSettings,
                              previous: CharacterSettings?) {
        let name = merged.portraitFileName
        if !name.isEmpty, name == content.settings.portraitFileName, let file = content.portraitFile {
            try? portraits.adopt(file: file, as: name)
        }
        if let old = previous?.portraitFileName, !old.isEmpty, old != name {
            try? portraits.remove(fileName: old)
        }
    }

    /// A conflict is merged as a fetched record is; a record or zone the server lacks goes up again.
    private func settle(_ failures: [CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave]) async {
        var conflicts: [CKRecord] = []
        var rejection: String?
        for failure in failures {
            let number = failure.record.recordID.recordName
            switch failure.error.code {
            case .serverRecordChanged:
                if let server = failure.error.serverRecord { conflicts.append(server) }
                changed(number)
            case .zoneNotFound:
                engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SettingsRecord.zoneID))])
                core.forgetServerCopy(of: number)
                changed(number)
            case .unknownItem:
                core.forgetServerCopy(of: number)
                changed(number)
            default:
                // The engine retries a temporary failure; anything else goes up again at the next launch.
                if !SettingsSyncCore.isTemporary(failure.error.code) { rejection = failure.error.localizedDescription }
            }
        }
        await merge(conflicts)
        if let rejection { await report(rejection) }
    }

    private func report(_ failure: String) async {
        await MainActor.run {
            store.reportFailure(SettingsSyncError(failure: failure))
        }
    }

    private func accountChanged(_ change: CKSyncEngine.Event.AccountChange.ChangeType) async {
        switch change {
        case .signIn, .switchAccounts:
            core.forgetServer()
            saveLedger()
            await uploadEverything()
        case .signOut:
            core.forgetServer()
            saveLedger()
        @unknown default:
            break
        }
    }

    /// The user deleted the app's iCloud data: forget the server, and keep this device's data without uploading
    /// it again. A zone deleted any other way is uploaded again.
    private func zonesDeleted(_ deletions: [CKDatabase.DatabaseChange.Deletion]) async {
        guard let deletion = deletions.first else { return }
        core.forgetServer()
        saveLedger()
        if deletion.reason != .purged { await uploadEverything() }
    }

    // MARK: - The ledger

    private func saveLedger() {
        guard let data = try? JSONEncoder().encode(core.ledger) else { return }
        try? FileManager.default.createDirectory(
            at: ledgerFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: ledgerFile, options: .atomic)
    }

    private static func readLedger(from file: URL) -> SyncLedger {
        guard let data = try? Data(contentsOf: file),
              let ledger = try? JSONDecoder().decode(SyncLedger.self, from: data) else { return SyncLedger() }
        return ledger
    }
}
