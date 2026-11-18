import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What went wrong saving or removing a portrait.
public struct PortraitError: Error, Equatable, LocalizedError {
    public let operation: String
    public let failure: String

    public var errorDescription: String? { "\(operation) failed: \(failure)" }
}

/// Keeps character portraits as PNG files no larger than 512 pixels, named by character number.
public struct PortraitStore: Sendable {
    public static let maximumSide = 512
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// `Application Support/Character Keeper/Portraits`.
    public static func standard() throws -> PortraitStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return PortraitStore(folder: support.appendingPathComponent("Character Keeper/Portraits", isDirectory: true))
    }

    public func url(forFileName name: String) -> URL? {
        name.isEmpty ? nil : folder.appendingPathComponent(name)
    }

    /// Scales the image down and saves it as the character's portrait, returning the file name to remember.
    public func save(imageData: Data, forCharacter number: String) throws -> String {
        let operation = "Saving the portrait for \(number)"
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, Self.thumbnailOptions) else {
            throw PortraitError(operation: operation, failure: "the file isn't an image")
        }
        let name = "\(number).png"
        try write(image, to: folder.appendingPathComponent(name), operation: operation)
        return name
    }

    public func remove(fileName name: String) throws {
        guard let file = url(forFileName: name), FileManager.default.fileExists(atPath: file.path) else { return }
        do { try FileManager.default.removeItem(at: file) } catch {
            throw PortraitError(operation: "Removing the portrait \(name)", failure: error.localizedDescription)
        }
    }

    private func write(_ image: CGImage, to file: URL, operation: String) throws {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw PortraitError(operation: operation, failure: error.localizedDescription)
        }
        let type = UTType.png.identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, type, 1, nil) else {
            throw PortraitError(operation: operation, failure: "can't write \(file.lastPathComponent)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PortraitError(operation: operation, failure: "can't write \(file.lastPathComponent)")
        }
    }

    private static var thumbnailOptions: CFDictionary {
        [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumSide
        ] as CFDictionary
    }
}
