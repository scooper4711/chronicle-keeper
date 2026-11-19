import Foundation

/// A made-up chronicle sheet for the demo account: its first character's newest session has one attached, so the
/// demo shows a session with its sheet without the user attaching anything.
public enum DemoChronicles {
    /// Puts the sheet in the library, where the store finds it like any the user attached. It goes in before the
    /// store looks, as the demo account is read more than once while the demo starts.
    public static func addSheet(to library: ChronicleLibrary) throws {
        let account = DemoAccount.snapshot()
        let roster = CharacterRoster(summaries: account.characters, sessions: account.sessions)
        guard let record = roster.characters.first, let newest = record.sessions.first else { return }
        let sheet = DemoBoons.page(
            "Chronicle Sheet\n\n\(newest.session.adventure.title)\n\(record.name)\n\n"
                + "Demo chronicle: not a real Organized Play document.")
        try library.save(sheet, to: library.fileURL(characterName: record.name, sessionID: newest.id))
    }
}
