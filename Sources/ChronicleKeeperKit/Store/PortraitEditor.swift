import Foundation

/// Changes one character's portrait, wherever the new picture comes from, and reports failures through the store.
@MainActor
public struct PortraitEditor {
    private let number: String
    private let store: CharacterStore
    private let portraits: PortraitStore

    public init(number: String, store: CharacterStore, portraits: PortraitStore) {
        self.number = number
        self.store = store
        self.portraits = portraits
    }

    /// Saves the picture as the portrait and removes the one it replaces.
    public func save(_ data: Data) {
        let previous = currentFileName
        guard let name = store.attempt({ try portraits.save(imageData: data, forCharacter: number) }) else { return }
        store.update(number) { $0.portraitFileName = name }
        if previous != name { _ = store.attempt { try portraits.remove(fileName: previous) } }
    }

    public func remove() {
        let previous = currentFileName
        store.update(number) { $0.portraitFileName = "" }
        _ = store.attempt { try portraits.remove(fileName: previous) }
    }

    public func paste(from pasteboard: any ImagePasteboard) {
        guard let data = pasteboard.imageData() else {
            report(PortraitError(operation: "Pasting the portrait", failure: "the clipboard has no picture"))
            return
        }
        save(data)
    }

    public func usePortrait(fromSheet sheet: URL, source: DemiplanePortraitSource) async {
        do {
            save(try await source.imageData(forSheet: sheet))
        } catch {
            report(error)
        }
    }

    private var currentFileName: String { store.allSettings[number]?.portraitFileName ?? "" }

    private func report(_ error: any Error) {
        _ = store.attempt { throw error }
    }
}
