import Foundation

/// Boon PDFs: finding the ones in the library and downloading the rest.
extension CharacterStore {
    /// Starts keeping boon PDFs, and finds the ones already in the library.
    public func useBoonDownloads(_ downloads: BoonDownloads) async {
        boonDownloads = downloads
        locateBoonFiles()
        if lastRefresh != nil { await downloadMissingBoons() }
    }

    /// Downloads each boon whose PDF isn't in the library yet: one another device already saved to iCloud Drive
    /// counts as there.
    public func downloadMissingBoons() async {
        guard let downloads = boonDownloads, !isDownloadingBoons else { return }
        isDownloadingBoons = true
        defer { isDownloadingBoons = false }
        let boons = snapshot?.boons ?? []
        for (boon, url) in missingBoons(boons, in: downloads.library) {
            do {
                try await download(boon, to: url, with: downloads)
            } catch {
                errorMessage = FailureMessage.text(for: error)
                return
            }
        }
    }

    private func download(_ boon: Boon, to url: URL, with downloads: BoonDownloads) async throws {
        guard let data = try await downloads.source.pdf(for: boon) else {
            unavailableBoons.insert(boon.id)
            return
        }
        try downloads.library.save(data, to: url)
        boonFiles[boon.id] = url
        unavailableBoons.remove(boon.id)
    }

    private func missingBoons(_ boons: [Boon], in library: BoonLibrary) -> [(Boon, URL)] {
        locateBoonFiles()
        let urls = library.fileURLs(for: boons)
        return boons.compactMap { boon in
            guard boonFiles[boon.id] == nil, let url = urls[boon.id] else { return nil }
            return (boon, url)
        }
    }

    func locateBoonFiles() {
        guard let library = boonDownloads?.library else { return }
        boonFiles = library.fileURLs(for: snapshot?.boons ?? []).filter { library.hasFile(at: $0.value) }
    }
}
