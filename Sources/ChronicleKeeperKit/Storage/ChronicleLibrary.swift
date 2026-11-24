import Foundation

/// The folder of chronicle sheet PDFs the user has attached to their own sessions: one folder per character number,
/// one PDF per session, keyed by event and session number. Neither has the character's name in it, as the player can
/// rename a character on paizo.com: a refresh or a rename never loses the link. Unlike boons, these
/// never come from paizo.com: the user attaches a PDF or photographs a paper sheet.
///
/// In a build with iCloud Documents it is `Chronicle Keeper/Chronicles` in the user's iCloud Drive, alongside
/// `Boons`, so it syncs the same way. Otherwise it is a `Chronicles` folder beside the app's other files, on this
/// device only.
public struct ChronicleLibrary: ICloudDocumentLibrary {
    public let folder: URL
    public let isInICloud: Bool

    public init(folder: URL, isInICloud: Bool = false) {
        self.folder = folder
        self.isInICloud = isInICloud
    }

    /// The iCloud Drive folder when this build and device have one, otherwise the local one. Looking up iCloud can
    /// take a while, so this runs away from the main actor.
    public static func standard(localFolder: URL) async -> ChronicleLibrary {
        let container = await Task.detached { FileManager.default.url(forUbiquityContainerIdentifier: nil) }.value
        guard let container else {
            return ChronicleLibrary(folder: localFolder.appendingPathComponent("Chronicles", isDirectory: true))
        }
        let chronicles = container.appendingPathComponent("Documents/Chronicles", isDirectory: true)
        return ChronicleLibrary(folder: chronicles, isInICloud: true)
    }

    /// Where a session's chronicle PDF goes: "123456-2001/5235126#2.pdf".
    public func fileURL(characterNumber: String, session: PlayedSession) -> URL {
        folder
            .appendingPathComponent(DocumentFileName.of(characterNumber), isDirectory: true)
            .appendingPathComponent(DocumentFileName.of(session.keyWithinCharacter) + ".pdf")
    }

    /// The sheets 1.0.0 filed by character name ("Name/5235126#2#Name.pdf"), by `PlayedSession.keyWithinCharacter`,
    /// so a sheet is found whatever the character was called when it was attached. One player has one character in
    /// a session, so the key alone tells whose it is.
    public func namedFiles() -> [String: URL] {
        var candidates: [String: [(folder: URL, name: String)]] = [:]
        // Built from `folder` rather than what listing it returns, which can resolve links ("/private/var").
        for characterFolder in contents(of: folder).map({ folder.appendingPathComponent($0.lastPathComponent) }) {
            for file in contents(of: characterFolder) {
                guard let (key, name) = Self.namedFile(file) else { continue }
                candidates[key, default: []].append((characterFolder, name))
            }
        }
        // iCloud names a conflicting copy "…#Name 2.pdf": the shortest name is the original, whichever is listed first.
        return candidates.compactMapValues { files in
            files.min { ($0.name.count, $0.name) < ($1.name.count, $1.name) }
                .map { $0.folder.appendingPathComponent($0.name) }
        }
    }

    /// Moves a sheet 1.0.0 filed by name to where it goes now, and says where it is. One that isn't on this device
    /// yet stays where it is, as only iCloud can move it then; so does one that can't be moved.
    public func moveNamedFile(_ named: URL, to url: URL) -> URL {
        guard isOnDevice(named) else { return named }
        do {
            try coordinatedMove(from: named, to: url)
        } catch {
            return named
        }
        removeIfEmpty(named.deletingLastPathComponent())
        return url
    }

    /// Writes a PDF, coordinated so iCloud sees a whole file.
    public func save(_ data: Data, to url: URL) throws {
        let operation = "Saving the chronicle \(url.deletingPathExtension().lastPathComponent)"
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try coordinatedWrite(data, to: url)
        } catch let error as RepositoryError {
            throw error
        } catch {
            throw RepositoryError(operation: operation, failure: error.localizedDescription)
        }
    }

    /// Removes a chronicle's PDF, if it has one.
    public func remove(at url: URL) throws {
        guard hasFile(at: url) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw RepositoryError(
                operation: "Removing the chronicle \(url.deletingPathExtension().lastPathComponent)",
                failure: error.localizedDescription)
        }
    }

    /// Moves a file, telling the coordinator it moved so iCloud keeps it as the same document, not a new one.
    private func coordinatedMove(from source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordinationError: NSError?
        var moveError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            writingItemAt: source, options: .forMoving, writingItemAt: destination, options: .forReplacing,
            error: &coordinationError
        ) { from, to in
            coordinator.item(at: from, willMoveTo: to)
            do {
                try FileManager.default.moveItem(at: from, to: to)
                coordinator.item(at: from, didMoveTo: to)
            } catch {
                moveError = error
            }
        }
        if let failure = coordinationError ?? moveError { throw failure }
    }

    /// Removes a folder 1.0.0 named after a character once nothing is left in it; one that can't be is left.
    private func removeIfEmpty(_ oldFolder: URL) {
        guard contents(of: oldFolder).isEmpty else { return }
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: oldFolder, options: .forDeleting, error: &coordinationError) {
            try? FileManager.default.removeItem(at: $0)
        }
    }

    /// A folder's files and folders, hidden ones (iCloud's placeholders) included; none when it can't be read.
    private func contents(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
    }

    /// A file named "event#session#name.pdf", or iCloud's ".event#session#name.pdf.icloud" for one, as the key and
    /// the PDF's own name.
    private static func namedFile(_ file: URL) -> (key: String, name: String)? {
        var name = file.lastPathComponent
        if name.hasPrefix("."), name.hasSuffix(".icloud") {
            name = String(name.dropFirst().dropLast(".icloud".count))
        }
        guard name.hasSuffix(".pdf") else { return nil }
        let parts = name.dropLast(".pdf".count).split(separator: "#", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        return ("\(parts[0])#\(parts[1])", name)
    }
}

/// A name that is safe as a file or folder name on the Mac, iPad and iPhone. Shared by `BoonLibrary` and
/// `ChronicleLibrary`, the two PDF libraries kept in the same iCloud Documents folder.
public enum DocumentFileName {
    public static func of(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? "File" : String(cleaned.prefix(120))
    }
}
