import ChronicleKeeperKit
import QuickLook
import SwiftUI

/// A session's chronicle sheet as a small button beside the adventure's title in the adventures table. While the
/// sheet has warnings the user hasn't cleared, the button is the warning's sign (R1.12).
struct ChronicleButton: View {
    let sheet: SessionSheet

    var body: some View {
        let state = State(isAttached: sheet.file != nil, hasWarnings: !sheet.warnings.isEmpty)
        // No label style here: the menu's own label is a symbol already, and a style would reach the items too.
        ChronicleMenu(sheet: sheet) { _ in
            if state.hasWarnings {
                Image(systemName: state.symbol).foregroundStyle(.orange)
            } else {
                Image(systemName: state.symbol)
            }
        }
        .menuStyle(.button).buttonStyle(.borderless)
        .accessibilityLabel(state.label)
        .help(state.help)
    }

    /// How the button looks and reads.
    private struct State {
        let isAttached: Bool
        let hasWarnings: Bool

        var symbol: String {
            if hasWarnings { return "exclamationmark.triangle.fill" }
            return isAttached ? "doc.text.fill" : "doc.badge.plus"
        }

        var label: String {
            if hasWarnings { return "Chronicle sheet, with warnings" }
            return isAttached ? "Chronicle sheet" : "Attach chronicle sheet"
        }

        var help: String {
            if hasWarnings { return "This adventure's chronicle sheet disagrees with paizo.com's record" }
            return isAttached ? "This adventure's chronicle sheet" : "Attach this adventure's chronicle sheet"
        }
    }
}

/// A session's chronicle sheet: attach a PDF, scan a paper one (iPhone and iPad), or open, share, read or remove
/// the one it already has. A PDF or a scan goes through the confirmation before it is kept (R1.11). The label is
/// told whether a sheet is attached.
struct ChronicleMenu<MenuLabel: View>: View {
    let sheet: SessionSheet
    @ViewBuilder let label: (_ isAttached: Bool) -> MenuLabel
    @State private var choosesFile = false
    @State private var scansSheet = false
    /// A scan, until the scanner has gone and the confirmation can come up.
    @State private var scanned: Data?
    @State private var candidate: SheetCandidate?
    @State private var preview: URL?

    var body: some View {
        Menu {
            if let file = sheet.file {
                Button { open(file) } label: { Label("Open", systemImage: "doc.text.magnifyingglass") }
                ShareLink(item: file) { Label("Share", systemImage: "square.and.arrow.up") }
                Button { readAttached() } label: { Label(readTitle, systemImage: "text.viewfinder") }
                Button(role: .destructive) { sheet.remove() } label: { Label("Remove", systemImage: "trash") }
            } else {
                Button { choosesFile = true } label: { Label("Attach PDF…", systemImage: "doc.badge.plus") }
                #if os(iOS)
                if DocumentScanner.isAvailable {
                    Button { scansSheet = true } label: { Label("Scan Sheet…", systemImage: "doc.viewfinder") }
                }
                #endif
            }
        } label: {
            label(sheet.file != nil)
        }
        .fileImporter(isPresented: $choosesFile, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result { confirm(PDFFile.data(at: url)) }
        }
        .quickLookPreview($preview)
        .sheetConfirmation($candidate, for: sheet)
        #if os(iOS)
        .fullScreenCover(isPresented: $scansSheet) {
            confirm(scanned)
            scanned = nil
        } content: {
            DocumentScanner { scanned = $0 }.ignoresSafeArea()
        }
        #endif
    }

    /// A sheet attached before the app read sheets has nothing read yet; one that was read can be checked again.
    private var readTitle: String {
        sheet.reading == nil ? "Read Sheet…" : "Check What Was Read…"
    }

    private func confirm(_ pdf: Data?) {
        candidate = pdf.map { SheetCandidate(pdf: $0) }
    }

    private func readAttached() {
        Task { candidate = await sheet.attachedCandidate() }
    }

    /// Shows the sheet once it is on this device, bringing it down from iCloud first when it was attached elsewhere.
    private func open(_ file: URL) {
        Task {
            guard await sheet.store.chronicleLibrary?.waitUntilOnDevice(file) ?? true else { return }
            preview = file
        }
    }
}

/// Takes a PDF dropped on a session as its chronicle sheet, through the confirmation (R1.13): from Finder on the
/// Mac, from Files beside the app on an iPad. One file at a time; a session that has a sheet asks before the
/// dropped one replaces it.
struct ChronicleDropTarget: ViewModifier {
    let sheet: SessionSheet
    @State private var candidate: SheetCandidate?
    /// A dropped PDF, while the user is asked whether it replaces the sheet the session has.
    @State private var replacement: SheetCandidate?
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .background(isTargeted ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .dropDestination(for: URL.self) { urls, _ in take(urls) } isTargeted: { isTargeted = $0 }
            .confirmationDialog(
                "Replace the Chronicle Sheet?", isPresented: isAsking, titleVisibility: .visible,
                presenting: replacement
            ) { dropped in
                Button("Replace", role: .destructive) { candidate = dropped }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("\(sheet.session.adventure.title) already has a chronicle sheet. The PDF you dropped takes "
                    + "its place when you keep it.")
            }
            .sheetConfirmation($candidate, for: sheet)
    }

    private var isAsking: Binding<Bool> {
        Binding { replacement != nil } set: { if !$0 { replacement = nil } }
    }

    /// A drop of several files, or of anything that isn't a PDF, is refused.
    private func take(_ urls: [URL]) -> Bool {
        guard urls.count == 1, let pdf = PDFFile.data(at: urls[0]) else { return false }
        let dropped = SheetCandidate(pdf: pdf)
        if sheet.file == nil { candidate = dropped } else { replacement = dropped }
        return true
    }
}

extension View {
    /// Lets a PDF be dropped here as the session's chronicle sheet.
    func chronicleDropTarget(for sheet: SessionSheet) -> some View {
        modifier(ChronicleDropTarget(sheet: sheet))
    }
}
