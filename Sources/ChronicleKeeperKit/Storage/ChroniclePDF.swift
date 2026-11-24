import CoreGraphics
import Foundation

/// Turns the pages of a scanned paper chronicle sheet into a PDF. Each page comes in as a JPEG that is already
/// upright: its pixels are drawn as they are, so a page that relied on an orientation tag would land sideways.
public enum ChroniclePDF {
    /// The longer side of each page, in points: a letter-size sheet's 11 inches. The picture keeps its own shape
    /// and every pixel, as the JPEG goes into the PDF as it is.
    static let longerSide: CGFloat = 792

    /// The PDF, one page per JPEG in order; nil when none of them can be read.
    public static func data(jpegPages: [Data]) -> Data? {
        let images = jpegPages.compactMap(image(fromJPEG:))
        guard !images.isEmpty else { return nil }
        let pdf = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdf as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil)
        else { return nil }
        for image in images {
            var box = CGRect(origin: .zero, size: pageSize(of: image))
            context.beginPage(mediaBox: &box)
            context.draw(image, in: box)
            context.endPage()
        }
        context.closePDF()
        return pdf as Data
    }

    /// The page a picture fills, its longer side `longerSide` long.
    static func pageSize(of image: CGImage) -> CGSize {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = longerSide / max(width, height)
        return CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
    }

    /// An image backed by the JPEG itself, which Quartz writes into the PDF without decoding and compressing it
    /// again.
    private static func image(fromJPEG data: Data) -> CGImage? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
