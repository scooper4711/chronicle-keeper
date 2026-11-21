import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ChronicleKeeperKit

@MainActor
private final class MemoryPasteboard: ImagePasteboard {
    var changeCount = 0
    var stored: Data?
    var hasImage: Bool { stored != nil }
    func imageData() -> Data? { stored }
}

private let sheetLink = "https://app.demiplane.com/nexus/pathfinder2e/character-sheet/"
    + "a5884413-857f-444c-a5d6-24d819632c8a"
private let imageLink = "https://\(DemiplanePortraitSource.imageHost)/portrait.png"

private func page(image: String) -> HTTPResponse {
    HTTPResponse(data: Data("<html><head><meta property=\"og:image\" content=\"\(image)\"/></head></html>".utf8))
}

private func pictureData() throws -> Data {
    let context = try #require(CGContext(
        data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(red: 0.5, green: 0, blue: 0.5, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
}

struct DemiplanePortraitSourceTests {
    @Test func aSheetLinkLosesItsQueryAndFragment() throws {
        let link = URL(string: sheetLink + "?tab=feats#top")
        #expect(DemiplanePortraitSource.sheetURL(from: link)?.absoluteString == sheetLink)
    }

    @Test(arguments: [
        "http://app.demiplane.com/nexus/pathfinder2e/character-sheet/a5884413-857f-444c-a5d6-24d819632c8a",
        "https://demiplane.com.example.org/nexus/pathfinder2e/character-sheet/a5884413-857f-444c-a5d6-24d819632c8a",
        "https://app.demiplane.com/nexus/pathfinder2e/character-sheet/abc",
        "https://app.demiplane.com/nexus/pathfinder2e/compendium/a5884413-857f-444c-a5d6-24d819632c8a",
        "https://pathbuilder2e.com/app.html?v=1"
    ])
    func otherLinksAreNotSheets(link: String) {
        #expect(DemiplanePortraitSource.sheetURL(from: URL(string: link)) == nil)
    }

    @Test func readsThePortraitThePageNames() async throws {
        let stub = StubHTTPClient()
        stub.on("character-sheet") { page(image: imageLink) }
        stub.on("portrait.png") { HTTPResponse(data: Data([1, 2, 3])) }
        let sheet = try #require(URL(string: sheetLink))
        let data = try await DemiplanePortraitSource(http: stub).imageData(forSheet: sheet)
        #expect(data == Data([1, 2, 3]))
    }

    @Test func artworkKeptElsewhereIsNotFetched() async throws {
        let stub = StubHTTPClient()
        stub.on("character-sheet") { page(image: "https://example.com/generic.png") }
        await #expect(throws: PortraitError.self) {
            _ = try await DemiplanePortraitSource(http: stub).imageData(forSheet: try #require(URL(string: sheetLink)))
        }
        #expect(stub.sentRequests.count == 1)
    }

    @Test func aRedirectAwayFromThePortraitStorageFails() async throws {
        let stub = StubHTTPClient()
        let elsewhere = URL(string: "https://example.com/portrait.png")
        stub.on("character-sheet") { page(image: imageLink) }
        stub.on("portrait.png") { HTTPResponse(data: Data([1]), finalURL: elsewhere) }
        await #expect(throws: PortraitError.self) {
            _ = try await DemiplanePortraitSource(http: stub).imageData(forSheet: try #require(URL(string: sheetLink)))
        }
    }
}

@MainActor
struct PortraitEditorTests {
    private let number = "123456-2001"
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("PortraitEditorTests-\(UUID().uuidString)", isDirectory: true)

    private struct Fixture {
        let editor: PortraitEditor
        let store: CharacterStore
        let portraits: PortraitStore
    }

    private func makeFixture() -> Fixture {
        let store = CharacterStore(repository: InMemoryCharacterRepository()) { SnapshotFactory.snapshot() }
        let portraits = PortraitStore(folder: folder)
        return Fixture(
            editor: PortraitEditor(number: number, store: store, portraits: portraits),
            store: store, portraits: portraits)
    }

    private func fileName(in store: CharacterStore) -> String { store.allSettings[number]?.portraitFileName ?? "" }

    @Test func pastingAPictureMakesItThePortrait() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixture = makeFixture()
        let (editor, store, portraits) = (fixture.editor, fixture.store, fixture.portraits)
        let pasteboard = MemoryPasteboard()
        pasteboard.stored = try pictureData()
        editor.paste(from: pasteboard)
        #expect(portraits.existingFile(named: fileName(in: store)) != nil)
    }

    @Test func pastingWithNoPictureSaysSoAndKeepsThePortrait() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixture = makeFixture()
        let (editor, store) = (fixture.editor, fixture.store)
        editor.save(try pictureData())
        let kept = fileName(in: store)
        editor.paste(from: MemoryPasteboard())
        #expect(fileName(in: store) == kept)
        #expect(store.errorMessage?.contains("no picture") == true)
    }

    @Test func aNewPortraitRemovesTheOldFile() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixture = makeFixture()
        let (editor, store, portraits) = (fixture.editor, fixture.store, fixture.portraits)
        editor.save(try pictureData())
        let old = fileName(in: store)
        editor.save(try pictureData())
        #expect(portraits.existingFile(named: old) == nil)
        editor.remove()
        #expect(fileName(in: store).isEmpty)
    }

    @Test func aDemiplanePortraitIsSaved() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixture = makeFixture()
        let (editor, store, portraits) = (fixture.editor, fixture.store, fixture.portraits)
        let picture = try pictureData()
        let stub = StubHTTPClient()
        stub.on("character-sheet") { page(image: imageLink) }
        stub.on("portrait.png") { HTTPResponse(data: picture) }
        await editor.usePortrait(
            fromSheet: try #require(URL(string: sheetLink)), source: DemiplanePortraitSource(http: stub))
        #expect(portraits.existingFile(named: fileName(in: store)) != nil)
    }

    @Test func aFailedDemiplaneReadReportsTheError() async throws {
        let fixture = makeFixture()
        let (editor, store) = (fixture.editor, fixture.store)
        let stub = StubHTTPClient()
        await editor.usePortrait(
            fromSheet: try #require(URL(string: sheetLink)), source: DemiplanePortraitSource(http: stub))
        #expect(fileName(in: store).isEmpty)
        #expect(store.errorMessage != nil)
    }
}
