import ChronicleKeeperKit
import SwiftUI

/// A session's date in the adventures table. A date paizo.com didn't give is marked with an info symbol (the
/// asterisk already marks held Chronicles in the level column) and says why on a tap, on a hover and to VoiceOver.
struct SessionDateCell: View {
    let date: SessionDate
    let eventName: String
    @State private var explains = false

    private var explanation: String { SessionDateText.explanation(eventName: eventName) }

    var body: some View {
        if date.isInferred {
            Button { explains = true } label: {
                HStack(spacing: 3) {
                    Text(SessionDateText.day(date)).monospacedDigit()
                    Image(systemName: "info.circle").imageScale(.small).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help(explanation)
            .accessibilityLabel("\(SessionDateText.day(date)), estimated")
            .accessibilityHint(explanation)
            .popover(isPresented: $explains) {
                Text(explanation)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 260)
                    .padding()
                    .presentationCompactAdaptation(.popover)
            }
        } else {
            Text(SessionDateText.day(date)).monospacedDigit()
        }
    }
}

/// How a session's date reads.
enum SessionDateText {
    /// "Sep 26, 2024", or "—" when neither paizo.com nor the session's event dates it.
    static func day(_ date: SessionDate) -> String {
        date.day.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—"
    }

    /// Why a date is marked as worked out. Some events have no name on paizo.com.
    static func explanation(eventName: String) -> String {
        let event = eventName.isEmpty ? "its event" : eventName
        return "paizo.com has no date for this session, so it's shown on the last day of \(event), "
            + "when a convention's Chronicles apply."
    }
}
