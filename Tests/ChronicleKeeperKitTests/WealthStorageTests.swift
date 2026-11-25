import CloudKit
import Foundation
import Testing
@testable import ChronicleKeeperKit

private let number = WealthFactory.number

private func settings(
    notes: String = "", purchases: [Purchase] = [], earned: [String: Int] = [:]
) -> CharacterSettings {
    var value = CharacterSettings(notes: notes)
    value.wealth = CharacterWealth(earned: earned)
    purchases.forEach { value.wealth.add($0) }
    return value
}

private func purchase(_ id: String) -> Purchase { WealthFactory.purchase(id, price: 100) }

struct WealthFileTests {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("chronicle-keeper-wealth-\(UUID().uuidString)")

    private var repository: FileCharacterRepository { FileCharacterRepository(folder: folder) }

    private func text(of name: String) throws -> String {
        try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
    }

    private func write(_ text: String, to name: String) throws {
        try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    @Test func theLedgerIsSavedApartFromTheSettings() throws {
        try repository.saveSettings([number: settings(notes: "n", purchases: [purchase("rope")])])
        #expect(try !text(of: "settings.json").contains("rope"))
        #expect(try text(of: "wealth.json").contains("rope"))
        let loaded = try #require(try repository.loadSettings()[number])
        #expect(loaded.notes == "n" && loaded.wealth.purchases["rope"] != nil)
    }

    @Test func settingsAnOlderVersionRewroteKeepTheLedger() throws {
        try repository.saveSettings([number: settings(notes: "n", purchases: [purchase("rope")])])
        // What 1.1.0 writes: only the fields it knows.
        try write(#"{"\#(number)": {"defaultTrack": "slow", "startingLevel": 1, "overrides": {}, "notes": "old"}}"#,
                  to: "settings.json")
        let loaded = try #require(try repository.loadSettings()[number])
        #expect(loaded.notes == "old" && loaded.defaultTrack == .slow)
        #expect(loaded.wealth.purchases["rope"] != nil)
    }

    @Test func settingsFromBeforeTheLedgerStillLoad() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try write(#"{"\#(number)": {"defaultTrack": "normal", "notes": "1.0"}}"#, to: "settings.json")
        let loaded = try #require(try repository.loadSettings()[number])
        #expect(loaded.notes == "1.0" && loaded.wealth.isEmpty)
    }

    @Test func aLedgerWithoutOtherSettingsLoads() throws {
        try repository.saveSettings([number: settings(earned: ["a": 5])])
        try write("{}", to: "settings.json")
        #expect(try repository.loadSettings()[number]?.wealth.earned == ["a": 5])
    }

    @Test func emptyLedgersArentWritten() throws {
        try repository.saveSettings([number: settings(notes: "n")])
        #expect(try text(of: "wealth.json").trimmingCharacters(in: .whitespacesAndNewlines) == "{\n\n}")
    }

    @Test func aBrokenLedgerFileIsReported() throws {
        try repository.saveSettings([:])
        try write("nonsense", to: "wealth.json")
        #expect(throws: RepositoryError.self) { try repository.loadSettings() }
    }
}

struct WealthFieldsTests {
    @Test func fieldsANewerVersionAddedSurviveASave() throws {
        let json = #"""
        {"purchases": {"x": {"id": "x", "name": "Wand", "unitPrice": 100, "access": {"boon": "B1", "level": 2}}},
         "earned": {}, "crafting": [1, true, null, "x"]}
        """#
        let wealth = try JSONDecoder().decode(CharacterWealth.self, from: Data(json.utf8))
        #expect(wealth.purchases["x"]?.quantity == 1)
        let again = try JSONDecoder().decode(CharacterWealth.self, from: JSONEncoder().encode(wealth))
        #expect(again == wealth)
        #expect(again.unknownFields.values["crafting"] == .array([.number(1), .bool(true), .null, .string("x")]))
        #expect(again.purchases["x"]?.unknownFields.values["access"]
            == .object(["boon": .string("B1"), "level": .number(2)]))
    }
}

struct WealthRecordTests {
    @Test func aRecordCarriesTheLedgerInItsOwnField() throws {
        let record = try SettingsSyncCore().record(
            for: number, settings: settings(notes: "n", purchases: [purchase("rope")]), portraitFile: nil)
        #expect(record["wealth"] is Data)
        let settingsData = try #require(record["settings"] as? Data)
        #expect(String(bytes: settingsData, encoding: .utf8)?.contains("rope") == false)
        let content = try #require(SettingsRecord.content(of: record))
        #expect(content.hasWealth && content.settings.wealth.purchases["rope"] != nil)
    }

    @Test func aRecordWithoutALedgerReadsAsHavingNone() throws {
        let content = try #require(SettingsRecord.content(of: oldBuildRecord(notes: "n")))
        #expect(!content.hasWealth && content.settings.wealth.isEmpty)
    }

    @Test func aRecordWithAnUnreadableLedgerIsSkipped() throws {
        let record = oldBuildRecord(notes: "n")
        record["wealth"] = Data("nonsense".utf8) as NSData
        #expect(SettingsRecord.content(of: record) == nil)
    }
}

struct WealthSyncTests {
    @Test func aSaveByAnOlderBuildDoesntDeleteTheLedger() throws {
        var core = SettingsSyncCore()
        let local = settings(purchases: [purchase("rope")])
        core.saved(try core.record(for: number, settings: local, portraitFile: nil))
        let result = core.received(oldBuildRecord(notes: "from 1.1.0"), local: local)
        let merged = try #require(result)
        #expect(merged.settings.notes == "from 1.1.0")
        #expect(merged.settings.wealth.purchases["rope"] != nil)
        #expect(merged.needsUpload)
        #expect(core.unsynced(in: [number: merged.settings]).isEmpty)
    }

    @Test func purchasesAddedOnTwoDevicesBothSurvive() throws {
        var core = SettingsSyncCore()
        let ancestor = settings(purchases: [purchase("rope")])
        core.saved(try core.record(for: number, settings: ancestor, portraitFile: nil))
        let remote = settings(purchases: [purchase("rope"), purchase("ipad")])
        let local = settings(purchases: [purchase("rope"), purchase("mac")])
        let incoming = try SettingsSyncCore().record(for: number, settings: remote, portraitFile: nil)
        let result = core.received(incoming, local: local)
        let merged = try #require(result)
        #expect(Set(merged.settings.wealth.purchases.keys) == ["rope", "ipad", "mac"])
        #expect(merged.needsUpload)
    }

    @Test func aLedgerEditIsUnsyncedUntilSaved() throws {
        var core = SettingsSyncCore()
        let agreed = settings(notes: "n")
        core.saved(try core.record(for: number, settings: agreed, portraitFile: nil))
        #expect(core.unsynced(in: [number: agreed]).isEmpty)
        #expect(core.unsynced(in: [number: settings(notes: "n", earned: ["a": 1])]) == [number])
    }

    @Test func theAgreedLedgerSurvivesARelaunch() throws {
        var core = SettingsSyncCore()
        core.saved(try core.record(for: number, settings: settings(earned: ["a": 1]), portraitFile: nil))
        let data = try JSONEncoder().encode(core.ledger)
        let reloaded = try JSONDecoder().decode(SyncLedger.self, from: data)
        #expect(reloaded.entries[number]?.agreed.wealth.earned == ["a": 1])
    }

    @Test func aSyncStateFromBeforeTheLedgerStillLoads() throws {
        var entry = SyncLedger.Entry(systemFields: nil, ancestor: CharacterSettings(notes: "n"))
        entry.ancestorWealth = nil
        #expect(entry.agreed.wealth.isEmpty && entry.agreed.notes == "n")
    }
}

struct WealthMergeTests {
    @Test func earnedGoldMergesPerAdventure() {
        let merged = WealthMerge.merge(
            local: CharacterWealth(earned: ["a": 1, "b": 2]), remote: CharacterWealth(earned: ["a": 1, "c": 3]),
            ancestor: CharacterWealth(earned: ["a": 1]))
        #expect(merged.earned == ["a": 1, "b": 2, "c": 3])
    }

    @Test func aPurchaseRemovedHereStaysRemoved() {
        let both = CharacterWealth(purchases: ["x": purchase("x")])
        let merged = WealthMerge.merge(local: CharacterWealth(), remote: both, ancestor: both)
        #expect(merged.purchases.isEmpty)
    }

    @Test func aPurchaseEditedHereWinsOverTheSamePurchaseThere() {
        var mine = purchase("x"), theirs = purchase("x")
        mine.quantity = 3
        theirs.name = "Renamed"
        let merged = WealthMerge.merge(
            local: CharacterWealth(purchases: ["x": mine]), remote: CharacterWealth(purchases: ["x": theirs]),
            ancestor: CharacterWealth(purchases: ["x": purchase("x")]))
        #expect(merged.purchases["x"] == mine)
    }

    @Test func startingFundsPickLikeAField() {
        let merged = WealthMerge.merge(
            local: CharacterWealth(), remote: CharacterWealth(startingFunds: 5), ancestor: CharacterWealth())
        #expect(merged.startingFunds == 5)
    }
}

/// A record as a build without the ledger saves it: settings and nothing else.
private func oldBuildRecord(notes: String) -> CKRecord {
    let record = CKRecord(recordType: SettingsRecord.recordType, recordID: SettingsRecord.recordID(for: number))
    let json = #"{"defaultTrack":"normal","notes":"\#(notes)","overrides":{},"startingLevel":1}"#
    record["settings"] = Data(json.utf8) as NSData
    return record
}
