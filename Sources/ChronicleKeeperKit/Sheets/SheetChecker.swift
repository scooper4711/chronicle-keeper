import Foundation

/// One way a chronicle sheet disagrees with paizo.com's record of its session, or with the ledger (R1.12). Reports
/// and hand-filled sheets both hold mistakes, so it is a warning the user clears and never a block.
public struct SheetMismatch: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        /// The sheet names another character than the session was reported for.
        case character
        /// The sheet is for another adventure than the session; or, for a sheet added ahead of its report, for
        /// an adventure paizo.com already lists for the character.
        case adventure
        /// The sheet's XP isn't what paizo.com's record gives, or isn't XP the adventure can give.
        case xp
        /// The sheet's gold or credits aren't what the ledger has for the adventure.
        case funds
    }

    public let kind: Kind
    /// Names the kind and the sheet's own value, so a sheet read again with another value warns again.
    public let id: String
    /// The disagreement, in words.
    public let message: String

    init(_ kind: Kind, value: String, message: String) {
        self.kind = kind
        id = "\(kind.rawValue):\(value)"
        self.message = message
    }
}

/// Compares what was read from a chronicle sheet with the session it is attached to and with the ledger (R1.12).
public struct SheetChecker: Sendable {
    private let record: CharacterRecord
    private let calculator: ProgressCalculator
    /// The user's characters' names by number, to name the one a sheet is for.
    private let names: [String: String]

    public init(record: CharacterRecord, roster: CharacterRoster) {
        self.record = record
        calculator = ProgressCalculator(campaign: record.campaign, eventDates: roster.eventDates)
        names = Dictionary(roster.characters.map { ($0.id, $0.name) }) { first, _ in first }
    }

    /// The warnings about a session's sheet that the user hasn't cleared; none for a session without a reading.
    public func warnings(for session: PlayedSession) -> [SheetMismatch] {
        guard let reading = record.settings.wealth.sheetReadings[session.keyWithinCharacter] else { return [] }
        return mismatches(of: reading, with: session).filter { !reading.clearedWarnings.contains($0.id) }
    }

    /// Every way a reading disagrees with a session, cleared or not: the confirmation shows them before the
    /// reading is kept, so a misread is corrected there (R1.11).
    public func mismatches(of reading: SheetReading, with session: PlayedSession) -> [SheetMismatch] {
        [character(reading, session), adventure(reading, session), xp(reading, session), funds(reading, session)]
            .compactMap { $0 }
    }

    // MARK: - Each warning

    /// Only the character's own part of the number is compared: every character of a player shares the Organized
    /// Play part, and names get mangled.
    private func character(_ reading: SheetReading, _ session: PlayedSession) -> SheetMismatch? {
        let number = record.id.split(separator: "-", maxSplits: 1).map(String.init)
        guard let part = reading.characterPart, number.count == 2, part != number[1] else { return nil }
        let sheets = named("\(number[0])-\(part)", shownAs: part)
        let own = named(record.id, shownAs: number[1])
        let whose = session.isReported ? "paizo.com reported this session for \(own)." : "You added it to \(own)."
        return SheetMismatch(
            .character, value: part, message: "The sheet is for character number \(sheets). \(whose)")
    }

    /// "2002, Pip Underbough", or only the number when it isn't one of the user's characters.
    private func named(_ number: String, shownAs part: String) -> String {
        names[number].map { "\(part), \($0)" } ?? part
    }

    /// A session whose title has no code can't be compared.
    private func adventure(_ reading: SheetReading, _ session: PlayedSession) -> SheetMismatch? {
        guard session.isReported else { return alreadyReported(reading) }
        guard let code = reading.code, let reported = AdventureClassifier.code(of: session.adventure),
              code != reported else { return nil }
        return SheetMismatch(
            .adventure, value: code,
            message: "The sheet is for \(code). This session is \(session.adventure.title).")
    }

    /// A sheet added ahead of its report goes to the session paizo.com lists for its adventure (R1.15). One that
    /// is still waiting beside such a session means that session has a sheet already, or that the number is wrong:
    /// a character plays an adventure once for credit.
    private func alreadyReported(_ reading: SheetReading) -> SheetMismatch? {
        guard let code = reading.code, let listed = record.sessions.first(where: { progress in
            progress.isReported && AdventureClassifier.code(of: progress.session.adventure) == code
        }) else { return nil }
        return SheetMismatch(
            .adventure, value: "listed:\(code)",
            message: "paizo.com already lists \(listed.session.adventure.title) for this character. A character "
                + "plays an adventure once for credit, so check the scenario number.")
    }

    /// XP the adventure can't give isn't counted (R2.11), and the warning says so. Otherwise the sheet's XP is
    /// compared with what paizo.com's record alone gives, and only where that is no guess: the Guide's XP for the
    /// adventure's kind, on a track the reputation or the campaign's rules settle.
    private func xp(_ reading: SheetReading, _ session: PlayedSession) -> SheetMismatch? {
        guard let xp = reading.xp else { return nil }
        let kind = AdventureClassifier.kind(of: session.adventure)
        var withSheet = CharacterSettings()
        withSheet.wealth.sheetReadings[session.keyWithinCharacter] = reading
        let written = XPText.of(xp)
        guard calculator.sheetCredit(of: session, kind: kind, settings: withSheet) != nil else {
            return SheetMismatch(
                .xp, value: String(xp),
                message: "The sheet gives \(written) XP, which this adventure can't give, so it isn't counted.")
        }
        // A session paizo.com doesn't list has no record to compare with.
        guard session.isReported else { return nil }
        let reported = calculator.progress(of: session, settings: CharacterSettings())
        let isCertain = reported.xpSource == .rules && reported.trackSource != .characterDefault
        guard isCertain, reported.xp != xp else { return nil }
        return SheetMismatch(
            .xp, value: String(xp),
            message: "The sheet gives \(written) XP. paizo.com's record gives \(XPText.of(reported.xp)).")
    }

    /// An empty field in the ledger is filled from the sheet and never disagrees with it (R5.11).
    private func funds(_ reading: SheetReading, _ session: PlayedSession) -> SheetMismatch? {
        guard let funds = reading.funds, let typed = record.settings.wealth.earned[session.keyWithinCharacter],
              typed != funds else { return nil }
        let currency = CampaignRules(campaign: record.campaign).currency
        return SheetMismatch(
            .funds, value: String(funds),
            message: "The sheet gives \(Money.format(funds, in: currency)). "
                + "The ledger has \(Money.format(typed, in: currency)).")
    }
}
