import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Where a copied picture comes from. The system pasteboard conforms; tests use one in memory, because the system's
/// exists only in a desktop session, which CI runners don't have.
@MainActor
public protocol ImagePasteboard: AnyObject {
    /// Grows whenever the contents change. Reading it doesn't ask the user for permission to paste.
    var changeCount: Int { get }
    /// Whether a picture is there. Reading it doesn't ask the user for permission to paste.
    var hasImage: Bool { get }
    func imageData() -> Data?
}

#if os(macOS)
extension NSPasteboard: ImagePasteboard {
    public var hasImage: Bool {
        // A file copied in Finder also carries its icon, which isn't the picture.
        types?.contains(.fileURL) == true ? copiedImageFile != nil : availableType(from: Self.imageTypes) != nil
    }

    public func imageData() -> Data? {
        if types?.contains(.fileURL) == true {
            return copiedImageFile.flatMap { try? Data(contentsOf: $0) }
        }
        return availableType(from: Self.imageTypes).flatMap { data(forType: $0) }
    }

    private var copiedImageFile: URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]
        return (readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first
    }

    private static var imageTypes: [NSPasteboard.PasteboardType] {
        [UTType.png, .tiff, .jpeg, .heic, .webP, .gif].map { NSPasteboard.PasteboardType($0.identifier) }
    }
}
#else
extension UIPasteboard: ImagePasteboard {
    public var hasImage: Bool { hasImages }

    public func imageData() -> Data? { image?.pngData() }
}
#endif

public enum SystemPasteboard {
    /// The pasteboard the app's users copy pictures to.
    @MainActor public static var general: any ImagePasteboard {
        #if os(macOS)
        NSPasteboard.general
        #else
        UIPasteboard.general
        #endif
    }
}
