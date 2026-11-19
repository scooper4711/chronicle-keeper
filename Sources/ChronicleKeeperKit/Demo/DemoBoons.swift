import CoreGraphics
import CoreText
import Foundation

/// Made-up boons for the demo account, and a one-page PDF for each, drawn on the spot.
public enum DemoBoons {
    static var boons: [Boon] {
        [
            boon("Valeria Stonebrook", "Wayfinder", "Gain a free wayfinder.", reward: "r1"),
            boon("Valeria Stonebrook", "Skillful Mentor (Envoy's Alliance)",
                 "Help low-level PCs at your table with skill checks.", reward: "r2"),
            boon("Pip Underbough", "Lantern Fair Keepsake", "A made-up boon that only the demo account has.",
                 reward: "r3"),
            boon("Zix-7", "Drift Beacon", "A made-up Starfinder boon that can't be downloaded yet.", reward: "r4")
        ]
    }

    /// The boon with reward "r4" stands for one paizo.com won't hand over yet.
    public struct Source: BoonSource {
        public init() {}

        public func pdf(for boon: Boon) async throws -> Data? {
            boon.id.hasSuffix("/r4") ? nil : DemoBoons.pdf(title: boon.name, text: boon.summary)
        }
    }

    private static func boon(_ character: String, _ name: String, _ summary: String, reward: String) -> Boon {
        var fields = BoonFields()
        fields.characterName = character
        fields.name = name
        fields.summary = summary
        fields.downloadURL = URL(string: "https://example.com/demo/boon?character=\(character.count)&reward=\(reward)")
            ?? URL(fileURLWithPath: "/")
        return Boon(fields: fields)
    }

    /// A letter-sized page with the boon's name and description, and a note that it is a demo.
    static func pdf(title: String, text: String) -> Data {
        page("\(title)\n\n\(text)\n\nDemo boon: not a real Organized Play document.")
    }

    /// A letter-sized PDF page of text.
    static func page(_ text: String) -> Data {
        let data = NSMutableData()
        var page = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &page, nil) else { return Data() }
        context.beginPDFPage(nil)
        draw(text, in: context, page: page)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private static func draw(_ text: String, in context: CGContext, page: CGRect) {
        let font = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
        let attributed = NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): font])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: page.insetBy(dx: 72, dy: 72), transform: nil)
        CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil), context)
    }
}
