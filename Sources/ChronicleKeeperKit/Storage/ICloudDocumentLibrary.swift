import Foundation

/// A folder of PDFs that iCloud Documents may keep in step across devices: the boon and chronicle libraries. A
/// file added on another device can be known here before its pages are, so it is brought down before it is used.
public protocol ICloudDocumentLibrary: Sendable {
    /// Whether the folder is in iCloud Drive; a local folder's files are always on the device.
    var isInICloud: Bool { get }
}

/// How long a file is waited for, and how often it is looked for meanwhile.
public enum ICloudDownload {
    /// A boon or chronicle PDF is a page or two; after this the user is told it hasn't arrived.
    public static let longest = Duration.seconds(60)
    static let checkInterval = Duration.milliseconds(250)
}

extension ICloudDocumentLibrary {
    /// Whether the PDF is there, including one iCloud knows about but hasn't downloaded to this device yet.
    public func hasFile(at url: URL) -> Bool {
        let files = FileManager.default
        return files.fileExists(atPath: url.path) || files.fileExists(atPath: Self.placeholder(of: url).path)
    }

    /// Asks iCloud to bring a PDF that is only in the cloud down to this device.
    public func download(_ url: URL) {
        guard isInICloud else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    /// Whether the PDF's pages are on this device, and not only iCloud's note that it exists: on iPhone and iPad
    /// that note is a `.icloud` file beside it, on the Mac a file of the same name with nothing in it yet.
    public func isOnDevice(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard isInICloud else { return true }
        // A URL keeps the resource values it read, which would hide a download that has since finished.
        var fresh = url
        fresh.removeAllCachedResourceValues()
        let status = try? fresh.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus
        return status != .notDownloaded
    }

    /// Asks iCloud for a PDF that isn't on this device yet and waits for it, looking again every so often. False
    /// when it hasn't arrived within the time given, or the wait was canceled.
    public func waitUntilOnDevice(_ url: URL, timeout: Duration = ICloudDownload.longest) async -> Bool {
        if isOnDevice(url) { return true }
        download(url)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            do { try await Task.sleep(for: ICloudDownload.checkInterval) } catch { return false }
            if isOnDevice(url) { return true }
        }
        return false
    }

    /// Writes a PDF, coordinated so iCloud sees a whole file.
    func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do { try data.write(to: target, options: .atomic) } catch { writeError = error }
        }
        if let failure = coordinationError ?? writeError { throw failure }
    }

    /// The file iCloud leaves on iPhone and iPad for one it hasn't downloaded: ".Name.pdf.icloud".
    static func placeholder(of url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
    }
}
