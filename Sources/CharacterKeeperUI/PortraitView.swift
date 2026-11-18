import CharacterKeeperKit
import ImageIO
import SwiftUI

/// A character's portrait, or their initials on the campaign's color when they have none.
struct PortraitView: View {
    let record: CharacterRecord
    let side: CGFloat
    @Environment(\.portraits) private var portraits

    var body: some View {
        Group {
            if let image = portraitImage {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                initials
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side / 5))
        .accessibilityHidden(true)
    }

    private var portraitImage: CGImage? {
        guard let url = portraits.url(forFileName: record.settings.portraitFileName),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private var initials: some View {
        let letters = record.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return ZStack {
            Rectangle().fill(record.campaign.color.gradient)
            Text(letters.isEmpty ? "?" : letters)
                .font(.system(size: side * 0.4, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

extension Campaign {
    /// A color per campaign, for portraits without a picture.
    var color: Color {
        switch self {
        case .pathfinder2: .indigo
        case .starfinder2: .teal
        case .pathfinder1: .brown
        case .starfinder1: .cyan
        case .other: .gray
        }
    }
}
