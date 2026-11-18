import Foundation

/// The folder of chronicle sheet PDFs the user has attached to their own sessions: one folder per character, one
/// PDF per session, keyed by the session's own stable ID (so a refresh never loses the link). Unlike boons, these
/// never come from paizo.com: the user attaches a PDF or photographs a paper sheet.
///
/// In a build with iCloud Documents it is `Chronicle Keeper/Chronicles` in the user's iCloud Drive, alongside
/// `Boons`, so it syncs the same way. Otherwise it is a `Chronicles` folder beside the app's other files, on this
/// device only.
public struct ChronicleLibrary: Sendable {
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

    /// Where a session's chronicle PDF goes, keyed by its stable ID (event code, session number and character).
    public func fileURL(characterName: String, sessionID: String) -> URL {
        folder
            .appendingPathComponent(DocumentFileName.of(characterName), isDirectory: true)
            .appendingPathComponent(DocumentFileName.of(sessionID) + ".pdf")
    }

    /// Whether the PDF is there, including one iCloud knows about but hasn't downloaded to this device yet.
    public func hasFile(at url: URL) -> Bool {
        let placeholder = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
        let files = FileManager.default
        return files.fileExists(atPath: url.path) || files.fileExists(atPath: placeholder.path)
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

    /// Asks iCloud to bring a PDF that is only in the cloud down to this device, for opening it.
    public func download(_ url: URL) {
        guard isInICloud else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    private func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do { try data.write(to: target, options: .atomic) } catch { writeError = error }
        }
        if let failure = coordinationError ?? writeError { throw failure }
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
