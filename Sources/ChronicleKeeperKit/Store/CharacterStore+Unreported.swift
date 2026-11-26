import Foundation

/// Chronicle sheets added before paizo.com lists their session (R1.14), and what happens when it does (R1.15).
extension CharacterStore {
    /// Whether a session has a chronicle sheet: its PDF, or what was read from one.
    public func hasSheet(_ session: PlayedSession, characterNumber: String) -> Bool {
        chronicleFiles[session.id] != nil || sheetReading(for: session, characterNumber: characterNumber) != nil
    }

    /// The character's reported sessions that have no chronicle sheet, newest first: where an unreported sheet
    /// can go when the user would rather attach it than delete it.
    public func sessionsWithoutSheet(of record: CharacterRecord) -> [SessionProgress] {
        record.sessions.filter { $0.isReported && !hasSheet($0.session, characterNumber: record.id) }
    }

    /// The session of another of the user's characters that an unreported sheet seems to be for: the same
    /// scenario number and event code. Nil when there is none, or the user chose to keep waiting.
    public func sessionElsewhere(for sheet: PlayedSession, of record: CharacterRecord) -> PendingSheetMatcher.Match? {
        guard !sheet.isReported else { return nil }
        let cleared = record.settings.wealth.sheetReadings[sheet.keyWithinCharacter]?.clearedWarnings ?? []
        return sheetMatcher.elsewhere.first { match in
            match.sheet.id == sheet.id && match.from == record.id && !cleared.contains(match.id)
        }
    }

    /// Files an unreported sheet under a reported session, of its own character or another, as the user chose.
    public func attach(_ match: PendingSheetMatcher.Match) {
        guard canSaveSettings else { return }
        file(match)
        chronicleFiles = locatedFiles()
    }

    /// Deletes an unreported sheet: its row, its PDF, what was read from it, its gold and its correction. The
    /// purchases made after it stay, in the ledger's last group (R5.8).
    public func deleteUnreportedSheet(_ sheet: PlayedSession, characterNumber: String) {
        guard !sheet.isReported, canSaveSettings else { return }
        if let library = chronicleLibrary {
            let url = chronicleFiles[sheet.id] ?? library.fileURL(characterNumber: characterNumber, session: sheet)
            guard attempt({ try library.remove(at: url) }) != nil else { return }
        }
        chronicleFiles[sheet.id] = nil
        update(characterNumber) { _ = $0.takeSheet(sheet.keyWithinCharacter) }
    }

    /// Gives each unreported sheet whose own character now has its session to that session (R1.15): the reading,
    /// the gold, the correction, the purchases after it and the links to it. Only the user's data moves here; the
    /// PDF follows when this device has it (`locatedFiles`). True when any sheet was adopted.
    @discardableResult
    func adoptReportedSheets() -> Bool {
        guard canSaveSettings else { return false }
        let adoptions = sheetMatcher.adoptions
        adoptions.forEach(file)
        return !adoptions.isEmpty
    }

    /// What follows keeping an unreported sheet: it goes to its session when paizo.com already lists one, and
    /// its adventure's name is looked up otherwise.
    func unreportedSheetWasKept() {
        if adoptReportedSheets() { chronicleFiles = locatedFiles() }
        nameUnreportedSheets()
    }

    private var sheetMatcher: PendingSheetMatcher {
        PendingSheetMatcher(characters: roster.characters) { number, session in
            hasSheet(session, characterNumber: number)
        }
    }

    private func file(_ match: PendingSheetMatcher.Match) {
        guard let id = match.sheet.unreportedID else { return }
        let key = match.sheet.keyWithinCharacter
        let pendingFile = ChronicleLibrary.pendingFile(characterNumber: match.from, id: id)
        if match.from == match.to {
            update(match.from) { $0.adopt(key, as: match.session, pendingFile: pendingFile) }
        } else {
            // The purchases made after it are the first character's own, and stay in that ledger.
            var taken: SheetTransfer?
            update(match.from) { taken = $0.takeSheet(key) }
            guard var transfer = taken else { return }
            transfer.reading.pendingFile = pendingFile
            update(match.to) { $0.file(transfer, under: match.session) }
        }
        relink(match)
    }

    /// Points every purchase linked to the sheet, on any character, at the session it now belongs to (R5.10).
    private func relink(_ match: PendingSheetMatcher.Match) {
        guard let owner = roster.characters.first(where: { $0.id == match.to }) else { return }
        let old = AccessLink.chronicleID(characterNumber: match.from, sessionKey: match.sheet.keyWithinCharacter)
        let link = AccessLink(session: match.session, of: owner)
        for record in roster.characters where record.settings.wealth.hasLink(to: old) {
            update(record.id) { $0.wealth.relink(from: old, to: link) }
        }
    }
}

// MARK: - The adventure's name

/// An unreported sheet whose adventure is known only by its number.
private struct UnnamedSheet {
    let characterNumber: String
    let key: String
    let code: String
    let campaign: Campaign
}

extension CharacterStore {
    /// Looks up, in the catalog covers come from, the name, levels and cover of each unreported sheet's adventure
    /// that is known only by its number, one pass at a time. A sheet names its adventure on its title line, which
    /// isn't read; paizo.com's own title takes over when the session is reported.
    func nameUnreportedSheets() {
        guard let finder = coverFinder, namingPass == nil else { return }
        let unnamed = unnamedSheets
        guard !unnamed.isEmpty else { return }
        namingPass = Task {
            for sheet in unnamed where !Task.isCancelled {
                guard let found = try? await finder.adventure(code: sheet.code, in: sheet.campaign) else { continue }
                name(sheet, as: found)
            }
            // A pass that signing out canceled leaves the next one alone.
            if !Task.isCancelled { namingPass = nil }
        }
    }

    /// Waits for the lookup under way, if there is one.
    func waitForNames() async {
        await namingPass?.value
    }

    private var unnamedSheets: [UnnamedSheet] {
        roster.characters.flatMap { record in
            record.sessions.map(\.session).compactMap { session -> UnnamedSheet? in
                // An adventure another session names needs no lookup.
                guard !session.isReported, session.adventure.productID.isEmpty,
                      let reading = record.settings.wealth.sheetReadings[session.keyWithinCharacter],
                      reading.title == nil, let code = reading.code else { return nil }
                return UnnamedSheet(
                    characterNumber: record.id, key: session.keyWithinCharacter, code: code,
                    campaign: record.campaign)
            }
        }
    }

    /// Keeps what the catalog says of a sheet's adventure, unless the sheet went or got another number meanwhile.
    private func name(_ sheet: UnnamedSheet, as found: AdventureEntry) {
        guard settings(for: sheet.characterNumber).wealth.sheetReadings[sheet.key]?.code == sheet.code else { return }
        update(sheet.characterNumber) { settings in
            settings.wealth.sheetReadings[sheet.key]?.title = found.title
            settings.wealth.sheetReadings[sheet.key]?.levels = found.levelRange
        }
        guard let cover = found.coverArt, var account = snapshot, account.covers[found.id] == nil else { return }
        account.covers[found.id] = cover
        snapshot = account
        attempt { try repository.saveSnapshot(account) }
    }
}
