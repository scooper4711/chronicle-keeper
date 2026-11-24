import ChronicleKeeperKit
import PDFKit
import QuickLook
import SwiftUI

/// A session's chronicle sheet as a small button beside the adventure's title in the adventures table.
struct ChronicleButton: View {
    let session: PlayedSession
    let characterNumber: String
    let store: CharacterStore

    var body: some View {
        let isAttached = store.chronicleFiles[session.id] != nil
        // No label style here: the menu's own label is a symbol already, and a style would reach the items too.
        ChronicleMenu(session: session, characterNumber: characterNumber, store: store) { isAttached in
            Image(systemName: isAttached ? "doc.text.fill" : "doc.badge.plus")
        }
        .menuStyle(.button).buttonStyle(.borderless)
        .accessibilityLabel(isAttached ? "Chronicle sheet" : "Attach chronicle sheet")
        .help(isAttached ? "This adventure's chronicle sheet" : "Attach this adventure's chronicle sheet")
    }
}

/// A session's chronicle sheet: attach a PDF, photograph a paper one (iPhone and iPad), or open, share or remove
/// the one it already has. The label is told whether a sheet is attached.
struct ChronicleMenu<MenuLabel: View>: View {
    let session: PlayedSession
    let characterNumber: String
    let store: CharacterStore
    @ViewBuilder let label: (_ isAttached: Bool) -> MenuLabel
    @State private var choosesFile = false
    @State private var choosesPhoto = false
    @State private var preview: URL?

    private var file: URL? { store.chronicleFiles[session.id] }

    var body: some View {
        Menu {
            if let file {
                Button { open(file) } label: { Label("Open", systemImage: "doc.text.magnifyingglass") }
                ShareLink(item: file) { Label("Share", systemImage: "square.and.arrow.up") }
                Button(role: .destructive) {
                    store.removeChronicle(from: session, characterNumber: characterNumber)
                } label: { Label("Remove", systemImage: "trash") }
            } else {
                Button { choosesFile = true } label: { Label("Attach PDF…", systemImage: "doc.badge.plus") }
                #if os(iOS)
                if CameraCapture.isAvailable {
                    Button { choosesPhoto = true } label: { Label("Take Photo…", systemImage: "camera") }
                }
                #endif
            }
        } label: {
            label(file != nil)
        }
        .fileImporter(isPresented: $choosesFile, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result { attach(contentsOf: url) }
        }
        .quickLookPreview($preview)
        #if os(iOS)
        .fullScreenCover(isPresented: $choosesPhoto) {
            CameraCapture { image in attach(image) }
        }
        #endif
    }

    /// Shows the sheet once it is on this device, bringing it down from iCloud first when it was attached elsewhere.
    private func open(_ file: URL) {
        Task {
            guard await store.chronicleLibrary?.waitUntilOnDevice(file) ?? true else { return }
            preview = file
        }
    }

    private func attach(contentsOf url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        store.attachChronicle(data, to: session, characterNumber: characterNumber)
    }

    #if os(iOS)
    private func attach(_ image: UIImage) {
        guard let page = PDFPage(image: image) else { return }
        let document = PDFDocument()
        document.insert(page, at: 0)
        guard let data = document.dataRepresentation() else { return }
        store.attachChronicle(data, to: session, characterNumber: characterNumber)
    }
    #endif
}

#if os(iOS)
/// The system camera, wrapped for SwiftUI: photographs a paper chronicle sheet.
struct CameraCapture: UIViewControllerRepresentable {
    let captured: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture

        init(_ parent: CameraCapture) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage { parent.captured(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif
