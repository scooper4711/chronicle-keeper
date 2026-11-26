import ChronicleKeeperKit
import PDFKit
import SwiftUI

/// A session's chronicle sheet as the views use it: whose it is, what the store holds of it, and what can be done
/// with it.
@MainActor
struct SessionSheet {
    let session: PlayedSession
    let record: CharacterRecord
    let store: CharacterStore

    /// The sheet's PDF in the chronicle library, when the session has one.
    var file: URL? { store.chronicleFiles[session.id] }

    /// What was read from the sheet and kept (R1.11).
    var reading: SheetReading? { store.sheetReading(for: session, characterNumber: record.id) }

    /// The warnings about the sheet that the user hasn't cleared (R1.12).
    var warnings: [SheetMismatch] { store.sheetWarnings(for: session, record: record) }

    var currency: Currency { CampaignRules(campaign: record.campaign).currency }

    func remove() {
        store.removeChronicle(from: session, characterNumber: record.id)
    }

    func clear(_ warning: SheetMismatch) {
        store.clearWarning(warning.id, for: session, characterNumber: record.id)
    }

    func useSheetAmount() {
        store.useSheetAmount(for: session, characterNumber: record.id)
    }

    /// The sheet the session has, to read it (again): brought down from iCloud first when it was attached on
    /// another device. Nil when it has none or it can't be read.
    func attachedCandidate() async -> SheetCandidate? {
        guard let file, await store.chronicleLibrary?.waitUntilOnDevice(file) ?? true,
              let pdf = try? Data(contentsOf: file) else { return nil }
        return SheetCandidate(pdf: pdf, isAttached: true)
    }
}

/// A file the user chose or dropped.
enum PDFFile {
    /// Its contents when it is a PDF on this device that can be opened; nil for anything else.
    static func data(at url: URL) -> Data? {
        guard url.isFileURL else { return nil }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), PDFDocument(data: data) != nil else { return nil }
        return data
    }
}
