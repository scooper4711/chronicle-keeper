import ChronicleKeeperKit
import SwiftUI
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// An item's Rexard icon, as Field Guide shows it before any item cards are read: from the table in the bundle's
/// `ItemIcons` folder and the pictures `scripts/add-artwork.sh` puts beside it. An item without one, a custom item,
/// or a build without the art, gets Field Guide's symbol for equipment instead.
struct ItemIcon: View {
    let itemID: String
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let image = ItemIcons.image(for: itemID) {
                image.resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "shield.lefthalf.filled").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The icons in the bundle, read once each.
@MainActor
enum ItemIcons {
    private static let folder = Bundle.module.url(forResource: "ItemIcons", withExtension: nil)
    private static let table: ItemIconTable = {
        guard let folder, let text = try? String(
            contentsOf: folder.appendingPathComponent("item-icons.tsv"), encoding: .utf8) else {
            return ItemIconTable(tsv: "")
        }
        return ItemIconTable(tsv: text)
    }()
    private static var images: [String: Image] = [:]

    static func image(for itemID: String) -> Image? {
        guard let folder, let file = table.icon(for: itemID) else { return nil }
        if let image = images[file] { return image }
        let url = folder.appendingPathComponent(file)
        #if canImport(AppKit)
        guard let picture = NSImage(contentsOf: url) else { return nil }
        let image = Image(nsImage: picture)
        #else
        guard let picture = UIImage(contentsOfFile: url.path) else { return nil }
        let image = Image(uiImage: picture)
        #endif
        images[file] = image
        return image
    }
}
