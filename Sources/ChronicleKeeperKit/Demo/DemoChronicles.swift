import Foundation

/// Made-up chronicle sheets for the demo account: its first character's newest session has one attached, and its
/// second character has one for a session paizo.com doesn't list yet, so the demo shows both without the user
/// attaching anything.
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

    /// The key of the sheet the demo's second character has ahead of its report (R1.14).
    static let unreportedKey = UnreportedSheet.key("demo-sheet")

    /// What that sheet is taken to say: an adventure the first character has played, so the demo knows its name
    /// and levels without a catalog, added two days before the demo's account was read.
    static var unreportedReading: SheetReading {
        let added = Date(timeIntervalSince1970: 1_795_000_000 - 2 * 86_400)
        var reading = SheetReading(source: .pdfText)
        reading.code = "6-05"
        reading.playerNumber = DemoAccount.playerNumber
        reading.characterPart = "2002"
        reading.xp = 4
        reading.funds = 14 * Money.copperPerGold
        reading.addedAt = added
        reading.playedOn = SheetDay.text(of: added)
        return reading
    }

    /// Puts the sheets in the library, where the store finds them like any the user attached. They go in before
    /// the store looks, as the demo account is read more than once while the demo starts.
    public static func addSheet(to library: ChronicleLibrary) throws {
        let account = DemoAccount.snapshot()
        let roster = CharacterRoster(
            summaries: account.characters, sessions: account.sessions, settings: DemoWealth.settings)
        let newest = roster.characters.first.flatMap { record in record.sessions.first.map { (record, $0.session) } }
        let unreported = roster.characters.flatMap { record in
            record.sessions.filter { !$0.isReported }.map { (record, $0.session) }
        }
        for (record, session) in [newest].compactMap(\.self) + unreported {
            let sheet = DemoBoons.page(
                "Chronicle Sheet\n\n\(session.adventure.title)\n\(record.name)\n\n"
                    + "Demo chronicle: not a real Organized Play document.")
            try library.save(sheet, to: library.fileURL(characterNumber: record.id, session: session))
        }
    }
}
