import CloudKit
import Foundation

/// A character's settings as a CloudKit record (plan, "iCloud sync"): record type `Character`, named by the
/// character number, with the settings as JSON, the ledger as JSON in a field of its own (which an older build never
/// sets, so the server keeps it), and the portrait as an asset.
public enum SettingsRecord {
    public static let recordType = "Character"
    public static let zoneID = CKRecordZone.ID(zoneName: "Characters", ownerName: CKCurrentUserDefaultName)

    enum Field {
        static let settings = "settings"
        static let portrait = "portrait"
        static let wealth = "wealth"
    }

    /// What a record holds: whose settings, the settings with the ledger, and the portrait's file while CloudKit
    /// keeps it.
    public struct Content: Sendable {
        public let number: String
        public let settings: CharacterSettings
        public let portraitFile: URL?
        /// Whether the record has a ledger at all. One saved only by an older build has none, which says nothing
        /// about the ledger, as opposed to an empty one.
        public let hasWealth: Bool
    }

    public static func recordID(for number: String) -> CKRecord.ID {
        CKRecord.ID(recordName: number, zoneID: zoneID)
    }

    /// Writes `settings` into `record` (a new one, or the server's last copy so the save isn't a conflict).
    public static func fill(_ record: CKRecord, with settings: CharacterSettings, portraitFile: URL?) throws {
        record[Field.settings] = try encoder.encode(settings) as NSData
        record[Field.wealth] = try encoder.encode(settings.wealth) as NSData
        record[Field.portrait] = portraitFile.map { CKAsset(fileURL: $0) }
    }

    /// The content of a record of this type; nil for any other record, or one whose settings or ledger can't be
    /// read (taking an unreadable ledger as empty would delete it here in the merge).
    public static func content(of record: CKRecord) -> Content? {
        guard record.recordType == recordType, record.recordID.zoneID == zoneID,
              let data = record[Field.settings] as? Data,
              var settings = try? JSONDecoder().decode(CharacterSettings.self, from: data) else { return nil }
        let wealthData = record[Field.wealth] as? Data
        if let wealthData {
            guard let wealth = try? JSONDecoder().decode(CharacterWealth.self, from: wealthData) else { return nil }
            settings.wealth = wealth
        }
        let asset = record[Field.portrait] as? CKAsset
        return Content(number: record.recordID.recordName, settings: settings, portraitFile: asset?.fileURL,
                       hasWealth: wealthData != nil)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }
}

extension CKRecord {
    /// The record's system fields only (its change tag), archived, so the next save of it isn't a conflict.
    var archivedSystemFields: Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    /// A record rebuilt from archived system fields; nil when `data` isn't such an archive.
    static func fromSystemFields(_ data: Data) -> CKRecord? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        return CKRecord(coder: unarchiver)
    }
}
