import Foundation

/// The words that mark a session paizo.com doesn't list yet, and the totals that include one (R1.14): an
/// unreported session must never pass for a reported one.
public enum UnreportedText {
    public static let badge = "Unreported"

    /// What the badge says in full, to VoiceOver and on a hover.
    public static let badgeHelp = "paizo.com doesn't list this session yet. It counts from your chronicle sheet."

    public static let banner = "paizo.com doesn't list this session yet. Its XP and gold come from your chronicle "
        + "sheet."

    /// The small line under an unreported adventure's title: "Not reported yet · added Nov 21".
    public static func caption(added: Date?) -> String {
        guard let added else { return "Not reported yet" }
        return "Not reported yet · added \(added.formatted(.dateTime.day().month(.abbreviated)))"
    }

    /// The adventures section's title: "Adventures (12)", or "Adventures (12 · 2 not reported)".
    public static func adventuresTitle(of record: CharacterRecord) -> String {
        let unreported = record.unreportedCount
        let notReported = unreported == 0 ? "" : " · \(unreported) not reported"
        return "Adventures (\(record.sessions.count)\(notReported))"
    }

    /// Under a level or a balance that counts unreported sessions; empty when it counts none.
    public static func totalsNote(count: Int) -> String {
        switch count {
        case ..<1: ""
        case 1: "Includes 1 session paizo.com doesn't have yet"
        default: "Includes \(count) sessions paizo.com doesn't have yet"
        }
    }

    /// What removing an unreported sheet does, asked before it is done. `purchases` are those made after it;
    /// `canAttach` says whether the character has a reported adventure without a sheet for it to go to.
    public static func removalMessage(purchases: Int, canAttach: Bool) -> String {
        var message = "Deleting removes the sheet, its XP and its gold from this character."
        if purchases == 1 { message += " The purchase made after it moves to the end of the ledger." }
        if purchases > 1 { message += " The \(purchases) purchases made after it move to the end of the ledger." }
        if canAttach {
            message += " If paizo.com lists the session under another scenario number, attach the sheet to that "
                + "adventure instead, and it keeps everything."
        }
        return message
    }

    /// What to tell the user about an unreported sheet whose session seems to be reported for another character.
    public static func elsewhere(adventure: String, character: String) -> String {
        "paizo.com reported \(adventure) for \(character), with this sheet's event code. Move the sheet there, or "
            + "keep waiting for the GM to correct the report."
    }
}
