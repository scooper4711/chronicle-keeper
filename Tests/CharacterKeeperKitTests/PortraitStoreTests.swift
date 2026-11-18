import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CharacterKeeperKit

struct PortraitStoreTests {
    private let store = PortraitStore(
        folder: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))

    @Test func savesAScaledDownPNGNamedByCharacter() throws {
        defer { try? FileManager.default.removeItem(at: store.folder) }
        let name = try store.save(imageData: try Self.pngData(width: 1600, height: 800), forCharacter: "123456-2001")
        #expect(name.hasPrefix("123456-2001-") && name.hasSuffix(".png"))
        let file = try #require(store.url(forFileName: name))
        let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == PortraitStore.maximumSide)
        #expect(image.height == PortraitStore.maximumSide / 2)
        #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
    }

    @Test func rejectsDataThatIsNotAnImage() {
        #expect(throws: PortraitError.self) {
            try store.save(imageData: Data("not an image".utf8), forCharacter: "123456-2001")
        }
    }

    @Test func removesAPortraitAndIgnoresAMissingOne() throws {
        defer { try? FileManager.default.removeItem(at: store.folder) }
        let name = try store.save(imageData: try Self.pngData(width: 10, height: 10), forCharacter: "123456-2002")
        try store.remove(fileName: name)
        #expect(!FileManager.default.fileExists(atPath: store.folder.appendingPathComponent(name).path))
        try store.remove(fileName: name)
        try store.remove(fileName: "")
        #expect(store.url(forFileName: "") == nil)
    }

    private static func pngData(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
