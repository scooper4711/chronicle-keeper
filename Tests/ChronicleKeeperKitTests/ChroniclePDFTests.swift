import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import ChronicleKeeperKit

/// A plain gray JPEG of the given size, as a scanned page would arrive.
private func jpeg(width: Int, height: Int) throws -> Data {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(gray: 0.5, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(
        CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

private func document(_ data: Data?) throws -> PDFDocument {
    let bytes = try #require(data)
    return try #require(PDFDocument(data: bytes))
}

struct ChroniclePDFTests {
    @Test func aPortraitScanMakesAPortraitLetterPage() throws {
        let pdf = try document(ChroniclePDF.data(jpegPages: [jpeg(width: 850, height: 1100)]))
        #expect(pdf.pageCount == 1)
        let bounds = try #require(pdf.page(at: 0)).bounds(for: .mediaBox)
        #expect(bounds.size == CGSize(width: 612, height: 792))
    }

    @Test func aLandscapeScanStaysLandscape() throws {
        let pdf = try document(ChroniclePDF.data(jpegPages: [jpeg(width: 1100, height: 850)]))
        let bounds = try #require(pdf.page(at: 0)).bounds(for: .mediaBox)
        #expect(bounds.size == CGSize(width: 792, height: 612))
    }

    @Test func eachScannedPageBecomesAPageInOrder() throws {
        let pages = [try jpeg(width: 850, height: 1100), try jpeg(width: 1100, height: 850)]
        let pdf = try document(ChroniclePDF.data(jpegPages: pages))
        #expect(pdf.pageCount == 2)
        #expect(try #require(pdf.page(at: 1)).bounds(for: .mediaBox).width == 792)
    }

    @Test func theJPEGGoesInWithoutBeingCompressedAgain() throws {
        let data = try #require(ChroniclePDF.data(jpegPages: [jpeg(width: 850, height: 1100)]))
        // Latin-1 reads any bytes, so the binary streams around the dictionary don't stop the search.
        let text = try #require(String(bytes: data, encoding: .isoLatin1))
        #expect(text.contains("/DCTDecode"))
    }

    @Test func pagesThatArentJPEGsAreLeftOut() throws {
        let pages = [Data("not a picture".utf8), try jpeg(width: 850, height: 1100)]
        #expect(try document(ChroniclePDF.data(jpegPages: pages)).pageCount == 1)
    }

    @Test func nothingReadableMakesNoPDF() {
        #expect(ChroniclePDF.data(jpegPages: []) == nil)
        #expect(ChroniclePDF.data(jpegPages: [Data("not a picture".utf8)]) == nil)
    }
}
