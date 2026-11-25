import SwiftUI

/// A section of the character page with a title that folds it away. Whether it's folded is kept per section, for
/// every character and across launches. What `trailing` shows on the title's right stays visible while it's folded.
struct CollapsibleSection<Trailing: View, Content: View>: View {
    let title: String
    let spacing: CGFloat
    let trailing: Trailing
    let content: Content
    @AppStorage private var isCollapsed: Bool

    /// `id` names the section in the user defaults (`section.<id>.collapsed`).
    init(
        _ title: String, id: String, spacing: CGFloat = 8,
        @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.spacing = spacing
        self.trailing = trailing()
        self.content = content()
        _isCollapsed = AppStorage(wrappedValue: false, "section.\(id).collapsed")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack {
                toggle
                Spacer()
                trailing
            }
            if !isCollapsed { content }
        }
    }

    private var toggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isCollapsed.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                Text(title).font(.headline)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(isCollapsed ? "Show this section" : "Hide this section")
        .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
        .accessibilityHint(isCollapsed ? "Shows this section" : "Hides this section")
    }
}

extension CollapsibleSection where Trailing == EmptyView {
    init(_ title: String, id: String, spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.init(title, id: id, spacing: spacing, trailing: { EmptyView() }, content: content)
    }
}
