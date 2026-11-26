import ChronicleKeeperKit
import SwiftUI

/// The sign on a purchase that may not be Society legal. Hovering shows why on the Mac and with an iPad's pointer;
/// tapping or clicking shows it in a popover, which is how the iPhone and a touch-only iPad see it. The popover
/// has the way to link the purchase to what allows it (R5.10).
struct LegalityWarning: View {
    static let linkTitle = "Link a Boon or Chronicle Sheet…"

    let marks: [LegalityMark]
    let link: () -> Void
    @State private var isShowingWhy = false

    var body: some View {
        Button { isShowingWhy = true } label: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .buttonStyle(.borderless)
        .help(PurchaseLegality.warning(for: marks))
        .accessibilityLabel("May not be Society legal")
        .accessibilityHint(marks.map(\.explanation).joined(separator: " "))
        .popover(isPresented: $isShowingWhy) {
            LegalityPopover(text: PurchaseLegality.warning(for: marks), action: Self.linkTitle) {
                isShowingWhy = false
                link()
            }
        }
    }
}

/// The sign on a purchase the user linked to a boon or a Chronicle Sheet: a green check that says what the link
/// waives, which one it is and whose, with the way to unlink it.
struct AccessCheck: View {
    let marks: [LegalityMark]
    let link: AccessLink
    let unlink: () -> Void
    @State private var isShowingWhy = false

    private var explanation: String { PurchaseLegality.explanation(of: marks, coveredBy: link) }

    var body: some View {
        Button { isShowingWhy = true } label: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
        .buttonStyle(.borderless)
        .help(explanation)
        .accessibilityLabel(link.linkedLabel)
        .accessibilityHint(explanation)
        .popover(isPresented: $isShowingWhy) {
            LegalityPopover(text: explanation, action: "Unlink") {
                isShowingWhy = false
                unlink()
            }
        }
    }
}

/// What a purchase's sign says when tapped, over the one thing to do about it.
private struct LegalityPopover: View {
    let text: String
    let action: String
    let run: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text).fixedSize(horizontal: false, vertical: true)
            Button(action, action: run)
        }
        .font(.callout)
        .frame(width: 300, alignment: .leading)
        .padding()
        .presentationCompactAdaptation(.popover)
    }
}
