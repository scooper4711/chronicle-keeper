import CoreGraphics
import Foundation
import PDFKit
import Vision
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Finds the lines of text in a picture of a page.
public protocol TextRecognizer: Sendable {
    func lines(in image: CGImage) async throws -> [RecognizedLine]
}

/// Text recognition by Vision, handwriting included, on the device. The only Vision code in the app.
public struct VisionTextRecognizer: TextRecognizer {
    public init() {}

    /// Runs away from the caller's actor: a page takes a few tenths of a second, the first one much longer.
    public func lines(in image: CGImage) async throws -> [RecognizedLine] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // The sheet's numbers and codes aren't words to correct.
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap(Self.line)
        }.value
    }

    /// Vision measures from the bottom of the picture; the lines measure from the top.
    private static func line(_ observation: VNRecognizedTextObservation) -> RecognizedLine? {
        guard let text = observation.topCandidates(1).first?.string else { return nil }
        let box = observation.boundingBox
        return RecognizedLine(
            text: text, box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
    }
}

/// A picture of a chronicle PDF's first page, the way up it is shown, for text recognition and for showing.
public enum SheetPage {
    /// The width text recognition gets, in pixels. At 1,600 it reads a sheet's printing but missed a lone
    /// handwritten "4" on a real one; from 2,000 up it reads it, in about a fifth of a second.
    public static let recognitionWidth: CGFloat = 2400

    public static func image(of pdf: Data, width: CGFloat = recognitionWidth) -> CGImage? {
        PDFDocument(data: pdf)?.page(at: 0).flatMap { image(of: $0, width: width) }
    }

    public static func image(of page: PDFPage, width pixelWidth: CGFloat = recognitionWidth) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let isSideways = page.rotation % 180 != 0
        let size = isSideways ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
        guard size.width > 0 else { return nil }
        let picture = page.thumbnail(
            of: CGSize(width: pixelWidth, height: pixelWidth * size.height / size.width), for: .mediaBox)
        #if os(macOS)
        return picture.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return picture.cgImage
        #endif
    }
}

extension SheetPage {
    /// The PDF with every page turned clockwise by a number of quarter turns (negative for counterclockwise), as
    /// the user turns a sheet that came in sideways; nil when it isn't a PDF.
    public static func turned(_ pdf: Data, quarterTurns: Int) -> Data? {
        guard let document = PDFDocument(data: pdf), document.pageCount > 0 else { return nil }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            page.rotation = (((page.rotation + quarterTurns * 90) % 360) + 360) % 360
        }
        return document.dataRepresentation()
    }

    /// A box given in fractions of the page as it is shown (`y` from the top), in the page's own points: the
    /// reverse of `PDFTextLines.unitBox`, for marking on the page where a value was read.
    public static func pageBox(of unitBox: CGRect, on page: PDFPage) -> CGRect {
        let media = page.bounds(for: .mediaBox)
        let upright = PDFTextLines.turned(unitBox, by: 360 - page.rotation)
        return CGRect(
            x: media.minX + upright.minX * media.width, y: media.maxY - upright.maxY * media.height,
            width: upright.width * media.width, height: upright.height * media.height)
    }
}

/// Reads a chronicle sheet's PDF (R1.10): from its own text where that gives a reward, otherwise by text
/// recognition on a picture of the page.
public struct SheetReader: Sendable {
    private let recognizer: any TextRecognizer

    public init(recognizer: any TextRecognizer = VisionTextRecognizer()) {
        self.recognizer = recognizer
    }

    public func reading(of pdf: Data) async -> SheetReading {
        await locatedReading(of: pdf).reading
    }

    /// The reading with where on the page each value was found (R1.11).
    public func locatedReading(of pdf: Data) async -> LocatedReading {
        let written = SheetInterpreter.locatedReading(of: PDFTextLines.lines(of: pdf), source: .pdfText)
        guard !Self.isComplete(written.reading), let image = SheetPage.image(of: pdf),
              let lines = try? await recognizer.lines(in: image) else { return written }
        let recognized = SheetInterpreter.locatedReading(of: lines, source: .recognized)
        // A blank sheet's own text still names the adventure, where recognition may find nothing at all.
        return recognized.reading.isEmpty ? written : recognized
    }

    /// Whether the PDF's own text gave a reward, as a sheet a program filled in does: a scan gives nothing, and a
    /// sheet whose values were written on by hand or flattened into a picture gives only its printing. The code
    /// doesn't count, as some sheets print none.
    private static func isComplete(_ reading: SheetReading) -> Bool {
        reading.xp != nil || reading.funds != nil
    }
}
