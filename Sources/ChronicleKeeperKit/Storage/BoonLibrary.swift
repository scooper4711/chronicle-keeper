import Foundation

/// The folder of boon PDFs: one folder per character, one PDF per boon, named as the Boons tab names them.
///
/// In a build with iCloud Documents it is `Chronicle Keeper/Boons` in the user's iCloud Drive, so iCloud keeps it
/// in step on every device and the user can open, print and share the PDFs from Finder and the Files app. Otherwise
/// it is a `Boons` folder beside the app's other files, on this device only.
public struct BoonLibrary: Sendable {
    public let folder: URL
    public let isInICloud: Bool

    public init(folder: URL, isInICloud: Bool = false) {
        self.folder = folder
        self.isInICloud = isInICloud
    }

    /// The iCloud Drive folder when this build and device have one, otherwise the local one. Looking up iCloud can
    /// take a while, so this runs away from the main actor.
    public static func standard(localFolder: URL) async -> BoonLibrary {
        let container = await Task.detached { FileManager.default.url(forUbiquityContainerIdentifier: nil) }.value
        guard let container else {
            return BoonLibrary(folder: localFolder.appendingPathComponent("Boons", isDirectory: true))
        }
        let boons = container.appendingPathComponent("Documents/Boons", isDirectory: true)
        return BoonLibrary(folder: boons, isInICloud: true)
    }

    /// Where each boon's PDF goes. Two boons of one character with the same name get paizo.com's reward key added,
    /// so neither replaces the other.
    public func fileURLs(for boons: [Boon]) -> [Boon.ID: URL] {
        let groups = Dictionary(grouping: boons) { "\($0.characterName)|\($0.name)" }
        var urls: [Boon.ID: URL] = [:]
        for boon in boons {
            let isShared = (groups["\(boon.characterName)|\(boon.name)"]?.count ?? 0) > 1
            let name = isShared ? "\(boon.name) (\(boon.id.split(separator: "/").last ?? ""))" : boon.name
            urls[boon.id] = folder
                .appendingPathComponent(Self.fileName(boon.characterName), isDirectory: true)
                .appendingPathComponent(Self.fileName(name) + ".pdf")
        }
        return urls
    }

    /// Whether the PDF is there, including one iCloud knows about but hasn't downloaded to this device yet.
    public func hasFile(at url: URL) -> Bool {
        let placeholder = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
        let files = FileManager.default
        return files.fileExists(atPath: url.path) || files.fileExists(atPath: placeholder.path)
    }

    /// Writes a PDF, coordinated so iCloud sees a whole file.
    public func save(_ data: Data, to url: URL) throws {
        let operation = "Saving the boon \(url.deletingPathExtension().lastPathComponent)"
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

    /// A name that is safe as a file or folder name on the Mac, iPad and iPhone.
    static func fileName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? "Boon" : String(cleaned.prefix(120))
    }
}
