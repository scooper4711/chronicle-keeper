import Foundation

/// XP as people write it: whole numbers plain, halves (slow-track quests) with one decimal.
public enum XPText {
    public static func of(_ xp: Double) -> String {
        xp.formatted(.number.precision(.fractionLength(0...1)))
    }
}

/// The small gray line under an adventure's title: "Scenario · 4 XP · 2 Rep", with "(4 lost)" after the XP when the
/// Applying Credit rule cost some, and without the reputation when the session gave none or the campaign has none.
public enum SessionCaption {
    public static func text(for progress: SessionProgress, showsReputation: Bool) -> String {
        var parts = [progress.kind.displayName, xp(of: progress)]
        if showsReputation, let reputation = progress.session.reputation {
            parts.append("\(XPText.of(reputation)) Rep")
        }
        return parts.joined(separator: " · ")
    }

    private static func xp(of progress: SessionProgress) -> String {
        let lost = progress.xpLost > 0 ? " (\(XPText.of(progress.xpLost)) lost)" : ""
        return "\(XPText.of(progress.xp)) XP\(lost)"
    }
}
