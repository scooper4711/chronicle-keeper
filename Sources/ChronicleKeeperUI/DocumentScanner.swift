#if os(iOS)
import ChronicleKeeperKit
import SwiftUI
import VisionKit

/// The system document scanner, wrapped for SwiftUI: scans a paper chronicle sheet. It finds the sheet's edges and
/// straightens it, and before handing the pages over lets the user check each one, rotate or crop it, or scan it
/// again. Hands over the PDF of the pages, or nothing when the user cancels.
struct DocumentScanner: UIViewControllerRepresentable {
    let scanned: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    /// False on the Simulator and on devices without a camera.
    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// VisionKit calls its delegate on the main thread but doesn't say so, hence `@preconcurrency`.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner

        init(_ parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan
        ) {
            let pages = (0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).uprightJPEG }
            if let pdf = ChroniclePDF.data(jpegPages: pages) { parent.scanned(pdf) }
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController, didFailWithError error: Error
        ) {
            parent.dismiss()
        }
    }
}

extension UIImage {
    /// The picture as the user saw it, as a JPEG whose pixels are the right way up: drawing it applies its
    /// orientation, which a PDF would otherwise ignore and show the page sideways.
    var uprightJPEG: Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        return upright.jpegData(compressionQuality: 0.8)
    }
}
#endif
