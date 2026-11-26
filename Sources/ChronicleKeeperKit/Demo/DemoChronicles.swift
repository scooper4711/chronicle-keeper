import Foundation

/// A made-up chronicle sheet for the demo account: its first character's newest session has one attached, so the
/// demo shows a session with its sheet without the user attaching anything.
public enum DemoChronicles {
    /// That session's key among its character's sessions (`PlayedSession.keyWithinCharacter`).
    static let sessionKey = "9007#7"

    /// What the demo's sheet is taken to say (R1.10): gold, which fills the ledger's field, and the number of
    /// another demo character, so the demo has a warning to read and clear (R1.12).
    static var reading: SheetReading {
        var reading = SheetReading(source: .pdfText)
        reading.code = "6-20"
        reading.playerNumber = DemoAccount.playerNumber
        reading.characterPart = "2002"
        reading.xp = 4
        reading.funds = 30 * Money.copperPerGold
        return reading
    }

    /// Puts the sheet in the library, where the store finds it like any the user attached. It goes in before the
    /// store looks, as the demo account is read more than once while the demo starts.
    public static func addSheet(to library: ChronicleLibrary) throws {
        let account = DemoAccount.snapshot()
        let roster = CharacterRoster(summaries: account.characters, sessions: account.sessions)
        guard let record = roster.characters.first, let newest = record.sessions.first else { return }
        let sheet = DemoBoons.page(
            "Chronicle Sheet\n\n\(newest.session.adventure.title)\n\(record.name)\n\n"
                + "Demo chronicle: not a real Organized Play document.")
        try library.save(sheet, to: library.fileURL(characterNumber: record.id, session: newest.session))
    }
}
