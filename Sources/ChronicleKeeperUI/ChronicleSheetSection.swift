import ChronicleKeeperKit
import PDFKit
import QuickLook
import SwiftUI

/// A session's chronicle sheet under its details, as a message shows its attachment: the pages themselves, with a
/// menu to open, share or remove the sheet, or to attach one.
struct ChronicleSheetSection: View {
    let session: PlayedSession
    let characterNumber: String
    let store: CharacterStore
    @State private var preview: URL?

    private var file: URL? { store.chronicleFiles[session.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Chronicle Sheet", systemImage: "paperclip").font(.headline)
                Spacer()
                ChronicleMenu(session: session, characterNumber: characterNumber, store: store) { isAttached in
                    Label(isAttached ? "Sheet" : "Attach", systemImage: isAttached ? "ellipsis.circle" : "plus")
                }
                .menuStyle(.button).buttonStyle(.bordered).fixedSize()
                .accessibilityIdentifier("chronicle-sheet-menu")
            }
            if let file {
                // A sheet attached in place of another gets its own pages.
                ChroniclePages(file: file, library: store.chronicleLibrary) { preview = file }.id(file)
            } else {
                Text(Self.invitation).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .quickLookPreview($preview)
    }

    private static var invitation: String {
        #if os(iOS)
        "No chronicle sheet is attached. Attach the PDF from your GM, or scan the paper sheet."
        #else
        "No chronicle sheet is attached. Attach the PDF from your GM."
        #endif
    }
}

/// The sheet's pages, drawn full width; a tap opens the sheet itself, to zoom, mark up or print. A sheet attached
/// on another device is brought down from iCloud first.
struct ChroniclePages: View {
    let file: URL
    let library: ChronicleLibrary?
    let open: () -> Void
    @State private var sheet = ChroniclePageImages.Sheet.loading
    /// Counts the user's "Try Again"s, each of which starts the download and the drawing over.
    @State private var attempt = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch sheet {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            case .downloading:
                ProgressView { Text("Downloading the sheet from iCloud…").foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, minHeight: 120)
            case .notOnDevice:
                Text("The sheet hasn't arrived from iCloud yet. Check that this device is online and signed in to "
                    + "iCloud.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Try Again") { attempt += 1 }
            case .unreadable:
                Text("The sheet can't be shown here.").foregroundStyle(.secondary)
                Button("Open the Sheet", action: open)
            case .pages(let pages, let pageCount):
                Button(action: open) { stack(of: pages) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Chronicle sheet")
                    .accessibilityHint("Opens the sheet")
                    .accessibilityIdentifier("chronicle-sheet-pages")
                if pageCount > pages.count {
                    Text("Showing \(pages.count) of \(pageCount) pages. Open the sheet for the rest.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .task(id: attempt) { await show() }
    }

    private func show() async {
        sheet = .loading
        if let library, !library.isOnDevice(file) {
            sheet = .downloading
            guard await library.waitUntilOnDevice(file) else {
                if !Task.isCancelled { sheet = .notOnDevice }
                return
            }
        }
        sheet = await ChroniclePageImages.sheet(at: file)
    }

    private func stack(of pages: [CGImage]) -> some View {
        VStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Image(decorative: pages[index], scale: 1)
                    .resizable()
                    .scaledToFit()
                    .overlay { Rectangle().stroke(.quaternary) }
            }
        }
    }
}

/// Draws a chronicle PDF's first pages as pictures, away from the main actor.
enum ChroniclePageImages {
    enum Sheet: Sendable {
        case loading
        /// iCloud is bringing the sheet down to this device.
        case downloading
        /// iCloud didn't bring the sheet down in time.
        case notOnDevice
        /// On this device, but not a PDF that can be drawn.
        case unreadable
        case pages([CGImage], pageCount: Int)
    }

    /// A chronicle sheet is one page; a longer PDF shows its start.
    private static let pageLimit = 3
    /// Sharp at full width on an iPad and in a Mac window.
    private static let pixelWidth: CGFloat = 1600

    static func sheet(at file: URL) async -> Sheet {
        await Task.detached(priority: .userInitiated) { render(file) }.value
    }

    private static func render(_ file: URL) -> Sheet {
        guard let document = PDFDocument(url: file), document.pageCount > 0 else { return .unreadable }
        let pages = (0..<min(document.pageCount, pageLimit)).compactMap { index in
            document.page(at: index).flatMap(image(of:))
        }
        return pages.isEmpty ? .unreadable : .pages(pages, pageCount: document.pageCount)
    }

    private static func image(of page: PDFPage) -> CGImage? {
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
