import ChronicleKeeperKit
import PDFKit
import SwiftUI

/// A chronicle sheet's PDF, large, for checking what was read from it (R1.11): PDFKit's own view, which zooms with
/// a pinch and scrolls, the same on the Mac, the iPad and the iPhone. The places values were read from are
/// outlined on the first page.
@MainActor
struct SheetPageView {
    let pdf: Data
    /// Changes when `pdf` does: comparing a number costs less than comparing a scan on every update.
    let version: Int
    /// Where values were read, in fractions of the page as it is shown, `y` from the top.
    let marks: [CGRect]

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// What the view shows now, so an update changes only what differs.
    final class Coordinator {
        var version: Int?
        var outlines: [PDFAnnotation] = []
    }

    fileprivate func makeView() -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = false
        view.backgroundColor = .clear
        return view
    }

    fileprivate func update(_ view: PDFView, _ coordinator: Coordinator) {
        if coordinator.version != version {
            view.document = PDFDocument(data: pdf)
            view.autoScales = true
            coordinator.version = version
            coordinator.outlines = []
        }
        guard let page = view.document?.page(at: 0) else { return }
        coordinator.outlines.forEach(page.removeAnnotation)
        coordinator.outlines = marks.map { Self.outline(of: $0, on: page) }
        coordinator.outlines.forEach(page.addAnnotation)
    }

    /// A box drawn a little outside the writing it marks. It is only on the copy shown: the PDF that is kept is
    /// the user's file as it came.
    private static func outline(of mark: CGRect, on page: PDFPage) -> PDFAnnotation {
        let bounds = SheetPage.pageBox(of: mark, on: page).insetBy(dx: -4, dy: -4)
        let outline = PDFAnnotation(bounds: bounds, forType: .square, withProperties: nil)
        outline.color = .systemOrange
        let border = PDFBorder()
        border.lineWidth = 1.5
        outline.border = border
        return outline
    }
}

#if os(macOS)
extension SheetPageView: NSViewRepresentable {
    func makeNSView(context: Context) -> PDFView { makeView() }
    func updateNSView(_ view: PDFView, context: Context) { update(view, context.coordinator) }
}
#else
extension SheetPageView: UIViewRepresentable {
    func makeUIView(context: Context) -> PDFView { makeView() }
    func updateUIView(_ view: PDFView, context: Context) { update(view, context.coordinator) }
}
#endif
