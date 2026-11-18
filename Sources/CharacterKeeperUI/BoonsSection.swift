import CharacterKeeperKit
import PDFKit
import QuickLook
import SwiftUI

/// The character's boons from the Boons tab, each with its PDF to open, share or print.
struct BoonsSection: View {
    let boons: [Boon]
    let store: CharacterStore
    @State private var preview: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Boons (\(boons.count))").font(.headline)
            if boons.isEmpty {
                Text("No boons on paizo.com for this character.").foregroundStyle(.secondary)
            }
            ForEach(boons) { boon in
                Divider()
                BoonRow(boon: boon, file: store.boonFiles[boon.id], state: state(of: boon)) { preview = $0 }
            }
            if let library = store.boonDownloads?.library, !boons.isEmpty {
                Text(library.isInICloud
                     ? "The PDFs are in iCloud Drive, in Character Keeper › Boons, on all your devices."
                     : "The PDFs are kept on this device only.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .quickLookPreview($preview)
    }

    private func state(of boon: Boon) -> BoonRow.State {
        if store.boonFiles[boon.id] != nil { return .saved }
        if store.unavailableBoons.contains(boon.id) { return .unavailable }
        return store.isDownloadingBoons ? .downloading : .notDownloaded
    }
}

/// One boon: its name, what it does and how many uses are left, and its PDF's buttons.
struct BoonRow: View {
    enum State { case saved, downloading, notDownloaded, unavailable }

    let boon: Boon
    let file: URL?
    let state: State
    let open: (URL) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(boon.name)
                Text(boon.summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                if let uses = usesText {
                    Text(uses).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            actions
        }
        .font(.callout)
    }

    private var usesText: String? {
        guard boon.isConsumable else { return boon.quantity > 1 ? "×\(boon.quantity)" : nil }
        return boon.remainingUses.map { "Consumable · \($0) left" } ?? "Consumable"
    }

    @ViewBuilder private var actions: some View {
        switch state {
        case .saved:
            if let file { BoonFileButtons(file: file, open: open) }
        case .downloading:
            ProgressView().controlSize(.small)
        case .notDownloaded:
            Text("Not downloaded").font(.caption).foregroundStyle(.secondary)
        case .unavailable:
            Text("Not available yet").font(.caption).foregroundStyle(.secondary)
                .help("paizo.com didn't hand over this boon's PDF; some boons need an adventure played first")
        }
    }
}

/// Open, Share and Print for a saved boon PDF.
struct BoonFileButtons: View {
    let file: URL
    let open: (URL) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button { open(file) } label: { Label("Open", systemImage: "doc.text.magnifyingglass") }
                .help("Open the boon's PDF")
            ShareLink(item: file) { Label("Share", systemImage: "square.and.arrow.up") }
                .help("Send the boon's PDF, for example to your GM")
            Button { BoonPrinter.print(file) } label: { Label("Print", systemImage: "printer") }
                .help("Print the boon")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }
}

/// Prints a PDF with the system's print panel.
@MainActor
enum BoonPrinter {
    static func print(_ file: URL) {
        #if os(macOS)
        guard let document = PDFDocument(url: file),
              let operation = document.printOperation(for: .shared, scalingMode: .pageScaleToFit, autoRotate: true)
        else { return }
        operation.runModal(for: NSApp.keyWindow ?? NSWindow(), delegate: nil, didRun: nil, contextInfo: nil)
        #else
        let controller = UIPrintInteractionController.shared
        controller.printingItem = file
        controller.present(animated: true)
        #endif
    }
}
