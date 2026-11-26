import Foundation

/// The chronicle sheets' PDFs (R1.8): attaching and removing them, and finding them in the library.
extension CharacterStore {
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
        // A sheet filed elsewhere that it replaces: by name, as 1.0.0 did, or still in the pending folder.
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

    /// Finds each session's sheet, and gives every sheet added ahead of its report to the session paizo.com now
    /// lists for it (R1.15). Runs after loading, after a refresh and when the library is known.
    func locateChronicleFiles() {
        guard chronicleLibrary != nil else { return }
        chronicleFiles = locatedFiles()
        guard adoptReportedSheets() else { return }
        chronicleFiles = locatedFiles()
    }

    /// Each session's sheet in the library, by the session's ID. A sheet that isn't where it goes is moved there:
    /// one 1.0.0 filed by the character's name, and one that waited in the pending folder for its session.
    func locatedFiles() -> [String: URL] {
        guard let library = chronicleLibrary else { return [:] }
        let finder = SheetFileFinder(library: library, namedFiles: library.namedFiles())
        var files: [String: URL] = [:]
        for record in roster.characters {
            for session in record.sessions.map(\.session) {
                files[session.id] = finder.file(of: session, record: record)
            }
        }
        return files
    }
}

/// Finds one session's sheet in the library.
private struct SheetFileFinder {
    let library: ChronicleLibrary
    /// The sheets 1.0.0 filed by character name, by session key.
    let namedFiles: [String: URL]

    func file(of session: PlayedSession, record: CharacterRecord) -> URL? {
        let url = library.fileURL(characterNumber: record.id, session: session)
        if library.hasFile(at: url) { return url }
        if let named = namedFiles[session.keyWithinCharacter] { return library.moveNamedFile(named, to: url) }
        let reading = record.settings.wealth.sheetReadings[session.keyWithinCharacter]
        guard let pending = reading?.pendingFile.map(library.pendingURL), library.hasFile(at: pending) else {
            return nil
        }
        return library.adopt(pending, to: url)
    }
}
