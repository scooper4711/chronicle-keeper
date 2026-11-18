import CloudKit
import Foundation
import Testing
@testable import CharacterKeeperKit

private let number = "123456-2001"

private func settings(
    notes: String = "", track: Track = .normal, overrides: [String: SessionOverride] = [:], link: String = ""
) -> CharacterSettings {
    var value = CharacterSettings(defaultTrack: track, overrides: overrides, notes: notes)
    value.characterSheetLink = link
    return value
}

struct SettingsMergeTests {
    @Test func editsOnBothDevicesBothSurvive() {
        let ancestor = settings()
        let local = settings(notes: "Typed on the Mac")
        let remote = settings(link: "https://pathbuilder.example/1")
        let merged = SettingsMerge.merge(local: local, remote: remote, ancestor: ancestor)
        #expect(merged.notes == "Typed on the Mac")
        #expect(merged.characterSheetLink == "https://pathbuilder.example/1")
    }

    @Test func aFieldChangedHereWinsOverTheSameFieldChangedThere() {
        let merged = SettingsMerge.merge(
            local: settings(track: .slow), remote: settings(notes: "x", track: .normal), ancestor: settings())
        #expect(merged.defaultTrack == .slow)
        #expect(merged.notes == "x")
    }

    @Test func overridesMergePerSession() {
        let slow = SessionOverride(track: .slow), xp = SessionOverride(xp: 2)
        let ancestor = settings(overrides: ["a": slow, "gone": slow])
        let local = settings(overrides: ["a": slow, "b": slow])
        let remote = settings(overrides: ["a": xp, "gone": slow, "c": xp])
        let merged = SettingsMerge.merge(local: local, remote: remote, ancestor: ancestor)
        #expect(merged.overrides == ["a": xp, "b": slow, "c": xp])
    }

    @Test func anEmptyOverrideCountsAsNone() {
        let merged = SettingsMerge.merge(
            local: settings(overrides: ["a": SessionOverride()]), remote: settings(), ancestor: settings())
        #expect(merged.overrides.isEmpty)
    }
}

struct SettingsRecordTests {
    @Test func aRecordCarriesTheSettingsAndThePortrait() throws {
        let portrait = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try Data([1, 2, 3]).write(to: portrait)
        defer { try? FileManager.default.removeItem(at: portrait) }
        let record = try SettingsSyncCore().record(for: number, settings: settings(notes: "n"), portraitFile: portrait)
        #expect(record.recordType == "Character")
        #expect(record.recordID.zoneID.zoneName == "Characters")
        let content = try #require(SettingsRecord.content(of: record))
        #expect(content.number == number)
        #expect(content.settings.notes == "n")
        #expect(content.portraitFile == portrait)
    }

    @Test func recordsOfOtherKindsAreIgnored() {
        let other = CKRecord(recordType: "Other", recordID: SettingsRecord.recordID(for: number))
        #expect(SettingsRecord.content(of: other) == nil)
        let unreadable = CKRecord(recordType: "Character", recordID: SettingsRecord.recordID(for: number))
        unreadable["settings"] = Data("not json".utf8) as NSData
        #expect(SettingsRecord.content(of: unreadable) == nil)
    }

    @Test func settingsFromAnOlderVersionStillOpen() throws {
        let old = Data(#"{"defaultTrack":"slow","notes":"hi"}"#.utf8)
        let decoded = try JSONDecoder().decode(CharacterSettings.self, from: old)
        #expect(decoded.defaultTrack == .slow)
        #expect(decoded.notes == "hi")
        #expect(decoded.overrides.isEmpty && decoded.portraitFileName.isEmpty && decoded.xpAdjustment == 0)
    }
}

struct SettingsSyncCoreTests {
    private func serverRecord(_ value: CharacterSettings) throws -> CKRecord {
        try SettingsSyncCore().record(for: number, settings: value, portraitFile: nil)
    }

    @Test func aRecordFromAnotherDeviceIsTakenWhenNothingChangedHere() throws {
        var core = SettingsSyncCore()
        let merged = try #require(core.received(try serverRecord(settings(notes: "from iPad")), local: nil))
        #expect(merged == .init(settings: settings(notes: "from iPad"), needsUpload: false))
        #expect(core.ledger.entries[number]?.ancestor.notes == "from iPad")
        #expect(core.ledger.entries[number]?.systemFields != nil)
    }

    @Test func aMergeWithLocalChangesGoesBackUp() throws {
        var core = SettingsSyncCore()
        let merged = try #require(
            core.received(try serverRecord(settings(notes: "from iPad")), local: settings(track: .slow)))
        #expect(merged.settings.notes == "from iPad")
        #expect(merged.settings.defaultTrack == .slow)
        #expect(merged.needsUpload)
    }

    @Test func aSaveBecomesTheAncestor() throws {
        var core = SettingsSyncCore()
        core.saved(try serverRecord(settings(notes: "sent")))
        #expect(core.ledger.entries[number]?.ancestor.notes == "sent")
        let next = try core.record(for: number, settings: settings(notes: "again"), portraitFile: nil)
        #expect(next.recordID == SettingsRecord.recordID(for: number))
    }

    @Test func forgettingTheServerKeepsNothingButStartsOver() throws {
        var core = SettingsSyncCore()
        core.saved(try serverRecord(settings(notes: "sent")))
        core.forgetServerCopy(of: number)
        #expect(core.ledger.entries[number]?.systemFields == nil)
        #expect(core.ledger.entries[number]?.ancestor.notes == "sent")
        core.forgetServer()
        #expect(core.ledger.entries.isEmpty)
        #expect(core.ledger.engineState == nil)
    }

    @Test func theLedgerSurvivesAFile() throws {
        var core = SettingsSyncCore()
        core.saved(try serverRecord(settings(notes: "sent")))
        let data = try JSONEncoder().encode(core.ledger)
        let read = try JSONDecoder().decode(SyncLedger.self, from: data)
        #expect(read.entries == core.ledger.entries)
    }
}
