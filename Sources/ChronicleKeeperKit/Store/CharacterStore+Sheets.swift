import Foundation

/// What was read from a session's chronicle sheet (R1.10 to R1.12): reading a PDF, keeping the reading the user
/// confirmed, and the warnings it raises.
extension CharacterStore {
    /// Reads a chronicle sheet's PDF on the device, away from the main actor.
    public func read(_ pdf: Data) async -> LocatedReading {
        await sheetReader.locatedReading(of: pdf)
    }

    /// The reading kept for a session's sheet, if it has one.
    public func sheetReading(for session: PlayedSession, characterNumber: String) -> SheetReading? {
        settings(for: characterNumber).wealth.sheetReadings[session.keyWithinCharacter]
    }

    /// Keeps the reading the user confirmed (R1.11), in place of an earlier one, whose cleared warnings stay
    /// cleared. The sheet's gold fills the ledger's field when that is empty, or still holds what the earlier
    /// reading put there; gold the user typed is never replaced (R5.11).
    public func keep(_ reading: SheetReading, for session: PlayedSession, characterNumber: String) {
        let key = session.keyWithinCharacter
        update(characterNumber) { settings in
            let earlier = settings.wealth.sheetReadings[key]
            var kept = reading
            kept.clearedWarnings.formUnion(earlier?.clearedWarnings ?? [])
            settings.wealth.sheetReadings[key] = kept
            let entered = settings.wealth.earned[key]
            if let funds = reading.funds, entered == nil || entered == earlier?.funds {
                settings.wealth.earned[key] = funds
            }
        }
    }

    /// The warnings about a session's sheet that the user hasn't cleared (R1.12).
    public func sheetWarnings(for session: PlayedSession, record: CharacterRecord) -> [SheetMismatch] {
        // Asked for every row of the adventures table, most of which have no reading.
        guard record.settings.wealth.sheetReadings[session.keyWithinCharacter] != nil else { return [] }
        return SheetChecker(record: record, roster: roster).warnings(for: session)
    }

    /// Clears one warning about a session's sheet. It comes back when the sheet is read again with another value.
    public func clearWarning(_ id: SheetMismatch.ID, for session: PlayedSession, characterNumber: String) {
        update(characterNumber) { settings in
            settings.wealth.sheetReadings[session.keyWithinCharacter]?.clearedWarnings.insert(id)
        }
    }

    /// Takes the sheet's gold or credits over what the user typed in the ledger (R5.11).
    public func useSheetAmount(for session: PlayedSession, characterNumber: String) {
        guard let funds = sheetReading(for: session, characterNumber: characterNumber)?.funds else { return }
        update(characterNumber) { $0.wealth.earned[session.keyWithinCharacter] = funds }
    }

    /// Forgets what was read from a sheet that was removed. The ledger's gold and the user's corrections stay.
    func forgetReading(of session: PlayedSession, characterNumber: String) {
        guard sheetReading(for: session, characterNumber: characterNumber) != nil else { return }
        update(characterNumber) { $0.wealth.sheetReadings[session.keyWithinCharacter] = nil }
    }
}
