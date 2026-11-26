import Foundation

/// What the user keeps for a chronicle sheet's session, lifted out of a character's settings to be filed under
/// another session (R1.15): what was read, the gold it gave and the correction to its track or XP.
struct SheetTransfer: Hashable, Sendable {
    var reading: SheetReading
    var earned: Int?
    var override: SessionOverride?
}

extension CharacterSettings {
    /// Takes out everything filed under an unreported sheet's key; nil when no sheet is filed there. Purchases
    /// stay where they are: `CharacterWealth.movePurchases` takes them along, or the ledger lists them last.
    mutating func takeSheet(_ key: String) -> SheetTransfer? {
        guard let reading = wealth.sheetReadings.removeValue(forKey: key) else { return nil }
        return SheetTransfer(
            reading: reading, earned: wealth.earned.removeValue(forKey: key),
            override: overrides.removeValue(forKey: key))
    }

    /// Files a sheet under a reported session. What the session has of its own stays: gold the user typed for it
    /// and a correction they made to it, which the sheet's warnings then compare with (R1.12).
    mutating func file(_ transfer: SheetTransfer, under session: PlayedSession) {
        let key = session.keyWithinCharacter
        var reading = transfer.reading
        // paizo.com says what the adventure is and when it was played from here on.
        (reading.title, reading.levels, reading.playedOn, reading.addedAt) = (nil, nil, nil, nil)
        wealth.sheetReadings[key] = reading
        if wealth.earned[key] == nil { wealth.earned[key] = transfer.earned }
        if override(for: session) == nil, let correction = transfer.override { setOverride(correction, for: session) }
    }

    /// Gives an unreported sheet of this character to one of its reported sessions, with the purchases bought and
    /// sold after it. `pendingFile` is where the PDF was filed, for the file to follow.
    mutating func adopt(_ key: String, as session: PlayedSession, pendingFile: String) {
        guard var transfer = takeSheet(key) else { return }
        transfer.reading.pendingFile = pendingFile
        file(transfer, under: session)
        wealth.movePurchases(from: key, to: session.keyWithinCharacter)
    }
}

extension CharacterWealth {
    /// Places the purchases bought or sold after one adventure after another.
    mutating func movePurchases(from key: String, to newKey: String) {
        for (id, purchase) in purchases {
            var moved = purchase
            if moved.boughtAfter == key { moved.boughtAfter = newKey }
            if moved.soldAfter == key { moved.soldAfter = newKey }
            purchases[id] = moved
        }
    }

    /// How many purchases were bought or sold after an adventure.
    public func purchaseCount(after key: String) -> Int {
        purchases.values.filter { $0.boughtAfter == key || $0.soldAfter == key }.count
    }

    /// Points the purchases linked to one Chronicle Sheet at another (R5.10), as when a sheet's session arrives
    /// and the sheet is filed under it.
    mutating func relink(from sourceID: String, to link: AccessLink) {
        for purchase in purchases.values where purchase.isLinked(to: sourceID) {
            purchases[purchase.id]?.accessLink = link
        }
    }

    /// Whether a purchase is linked to this Chronicle Sheet.
    func hasLink(to sourceID: String) -> Bool {
        purchases.values.contains { $0.isLinked(to: sourceID) }
    }
}

extension Purchase {
    /// Whether the purchase is linked to the Chronicle Sheet with this ID (`AccessLink.chronicleID`).
    func isLinked(to sourceID: String) -> Bool {
        accessLink?.kind == .chronicle && accessLink?.sourceID == sourceID
    }
}
