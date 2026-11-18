import CharacterKeeperKit
import SwiftUI

/// A faction's symbol from Paizo's Community Use Package, or nothing when the faction has none.
struct FactionSymbol: View {
    let faction: String
    var size: CGFloat = 32

    var body: some View {
        if let image = Self.image(for: faction) {
            image.resizable().scaledToFit().frame(width: size, height: size)
        }
    }

    private static func image(for faction: String) -> Image? {
        let name = FactionArt.symbolName(for: faction)
        guard !name.isEmpty,
              let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Factions"),
              let data = try? Data(contentsOf: url) else { return nil }
        #if canImport(AppKit)
        return NSImage(data: data).map(Image.init(nsImage:))
        #else
        return UIImage(data: data).map(Image.init(uiImage:))
        #endif
    }
}
