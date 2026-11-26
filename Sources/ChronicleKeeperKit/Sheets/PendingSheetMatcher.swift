import Foundation

/// Finds the reported session each unreported chronicle sheet belongs to (R1.15). A character plays an adventure
/// once for credit, so a sheet and a session of the same character with the same scenario number are the same
/// session, whenever each was dated. A sheet never matches another scenario number.
public struct PendingSheetMatcher: Sendable {
    /// An unreported sheet and the session paizo.com now lists for it.
    public struct Match: Hashable, Sendable {
        /// The session the app made from the sheet.
        public let sheet: PlayedSession
        /// The character the sheet was added to.
        public let from: String
        public let session: PlayedSession
        /// The character paizo.com reported the session for.
        public let to: String

        public init(sheet: PlayedSession, from: String, session: PlayedSession, to: String) {
            self.sheet = sheet
            self.from = from
            self.session = session
            self.to = to
        }

        /// Names the match among a sheet's cleared warnings, so "Keep Waiting" is remembered.
        public var id: String { "elsewhere:\(to)/\(session.keyWithinCharacter)" }
    }

    /// Sheets whose own character has the session: the sheet becomes that session's.
    public let adoptions: [Match]
    /// Sheets with no session under their own character, whose scenario number and event code are those of a
    /// session of another of the user's characters. Nothing moves on its own: the user is asked.
    public let elsewhere: [Match]

    /// `hasSheet` says whether a character's session has a chronicle sheet already, which then keeps it.
    public init(characters: [CharacterRecord], hasSheet: (CharacterRecord.ID, PlayedSession) -> Bool) {
        var taken: Set<String> = []
        var adoptions: [Match] = []
        var waiting: [(sheet: PlayedSession, record: CharacterRecord)] = []
        for record in characters {
            let open = Self.openSessions(of: record, hasSheet: hasSheet)
            for sheet in Self.sheets(of: record) {
                let free = open.filter { !taken.contains(Self.name($0, of: record)) }
                if let session = Self.session(for: sheet, among: free) {
                    taken.insert(Self.name(session, of: record))
                    adoptions.append(Match(sheet: sheet, from: record.id, session: session, to: record.id))
                } else {
                    waiting.append((sheet, record))
                }
            }
        }
        self.adoptions = adoptions
        elsewhere = waiting.compactMap { waiting in
            Self.elsewhere(waiting.sheet, of: waiting.record, in: characters) { number, session in
                hasSheet(number, session) || taken.contains("\(number)/\(session.keyWithinCharacter)")
            }
        }
    }

    // MARK: - The sheet's own character

    /// The character's unreported sheets, the one played first first, so two sheets of one adventure take its
    /// sessions in order.
    private static func sheets(of record: CharacterRecord) -> [PlayedSession] {
        record.sessions.map(\.session).filter { !$0.isReported }
            .sorted { ($0.date ?? .distantPast, $0.id) < ($1.date ?? .distantPast, $1.id) }
    }

    /// The reported sessions that have no sheet yet, oldest first.
    private static func openSessions(
        of record: CharacterRecord, hasSheet: (CharacterRecord.ID, PlayedSession) -> Bool
    ) -> [PlayedSession] {
        record.sessions.map(\.session).filter { $0.isReported && !hasSheet(record.id, $0) }.reversed()
    }

    /// The session with the sheet's scenario number; among several, the one with its event code, else the oldest.
    private static func session(for sheet: PlayedSession, among sessions: [PlayedSession]) -> PlayedSession? {
        guard let code = AdventureClassifier.code(of: sheet.adventure) else { return nil }
        let same = sessions.filter { AdventureClassifier.code(of: $0.adventure) == code }
        return same.first { hasSameEvent($0, as: sheet) } ?? same.first
    }

    // MARK: - Another character

    private static func elsewhere(
        _ sheet: PlayedSession, of record: CharacterRecord, in characters: [CharacterRecord],
        isTaken: (CharacterRecord.ID, PlayedSession) -> Bool
    ) -> Match? {
        guard let code = AdventureClassifier.code(of: sheet.adventure) else { return nil }
        for other in characters where other.id != record.id && other.campaign == record.campaign {
            let session = other.sessions.map(\.session).first { session in
                session.isReported && AdventureClassifier.code(of: session.adventure) == code
                    && hasSameEvent(session, as: sheet) && !isTaken(other.id, session)
            }
            if let session { return Match(sheet: sheet, from: record.id, session: session, to: other.id) }
        }
        return nil
    }

    /// Whether the sheet's event code was read and is the session's.
    private static func hasSameEvent(_ session: PlayedSession, as sheet: PlayedSession) -> Bool {
        !sheet.eventCode.isEmpty && sheet.eventCode == session.eventCode
    }

    private static func name(_ session: PlayedSession, of record: CharacterRecord) -> String {
        "\(record.id)/\(session.keyWithinCharacter)"
    }
}
