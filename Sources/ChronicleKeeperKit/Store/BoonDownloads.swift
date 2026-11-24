import Foundation

/// The boon library and where its PDFs come from.
public struct BoonDownloads: Sendable {
    public let library: BoonLibrary
    public let source: BoonSource

    public init(library: BoonLibrary, source: BoonSource) {
        self.library = library
        self.source = source
    }
}
