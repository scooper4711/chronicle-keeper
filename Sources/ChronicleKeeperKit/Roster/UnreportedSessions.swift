import Foundation

/// A chronicle sheet the user added before paizo.com lists its session (R1.14). What was read from it is kept with
/// the other readings, under a key of its own, and the app shows it as a session until the report arrives.
public enum UnreportedSheet {
    static let keyPrefix = "unreported/"

    /// The key an unreported sheet's reading, gold, correction and purchases are filed under.
    public static func key(_ id: String) -> String {
        keyPrefix + id
    }

    /// The sheet's ID when the key is an unreported sheet's.
    public static func id(ofKey key: String) -> String? {
        key.hasPrefix(keyPrefix) ? String(key.dropFirst(keyPrefix.count)) : nil
    }

    /// The session a sheet stands for until paizo.com has it: the adventure from the sheet's number, played by this
    /// character on the sheet's day. Everything only paizo.com knows (Game Master, reputation, points) is empty.
    public static func session(
        id: String, reading: SheetReading, for character: CharacterSummary, adventure: AdventureReference? = nil
    ) -> PlayedSession {
        var fields = PlayedSessionFields()
        fields.unreportedID = id
        fields.date = reading.playedOn.flatMap(SheetDay.date) ?? reading.addedAt
        fields.adventure = adventure ?? ownAdventure(of: reading)
        fields.points = SessionPoints(achievementPoints: 0, gmCredits: 0, campaign: character.campaign)
        fields.eventCode = reading.eventCode ?? ""
        fields.playerNumber = character.number
        fields.characterName = character.name
        return PlayedSession(fields: fields)
    }

    /// The adventure as the reading alone gives it: the name and levels a catalog gave, or only the number.
    private static func ownAdventure(of reading: SheetReading) -> AdventureReference {
        let title = reading.title ?? reading.code.map(AdventureClassifier.title(forCode:)) ?? "Chronicle Sheet"
        return AdventureReference(productID: "", title: title, summary: reading.levels?.summaryText ?? "")
    }
}

extension SheetReading {
    /// Completes the reading kept for an unreported sheet with what its session is made from: when it was added,
    /// the day played (today unless the user chose one) and, while its number is the same, the name and levels
    /// looked up for its adventure.
    mutating func completeUnreported(after earlier: SheetReading?, now: Date = Date()) {
        // Whole seconds, so the date reads back equal from every file and record it is saved in.
        addedAt = earlier?.addedAt ?? Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down))
        playedOn = playedOn ?? earlier?.playedOn ?? SheetDay.text(of: now)
        if let earlier, earlier.code == code { (title, levels) = (earlier.title, earlier.levels) }
    }
}

/// Builds each character's unreported sessions from the readings kept for them.
struct UnreportedSessions: Sendable {
    /// The adventures paizo.com's sessions name, by campaign and code: another character's session of the same
    /// adventure gives its title, levels and product as paizo.com has them.
    private let known: [String: AdventureReference]

    init(sessions: [PlayedSession]) {
        var known: [String: AdventureReference] = [:]
        for session in sessions {
            guard let code = AdventureClassifier.code(of: session.adventure) else { continue }
            let key = Self.key(session.campaign, code)
            if known[key] == nil { known[key] = session.adventure }
        }
        self.known = known
    }

    /// The character's unreported sessions, the one added last first, as paizo.com lists the newest first.
    func sessions(of character: CharacterSummary, settings: CharacterSettings) -> [PlayedSession] {
        settings.wealth.sheetReadings
            .compactMap { key, reading in UnreportedSheet.id(ofKey: key).map { (id: $0, reading: reading) } }
            .sorted { ($0.reading.addedAt ?? .distantPast, $0.id) > ($1.reading.addedAt ?? .distantPast, $1.id) }
            .map { sheet in
                let adventure = sheet.reading.code.flatMap { known[Self.key(character.campaign, $0)] }
                return UnreportedSheet.session(
                    id: sheet.id, reading: sheet.reading, for: character, adventure: adventure)
            }
    }

    private static func key(_ campaign: Campaign, _ code: String) -> String {
        "\(campaign.shortName)|\(code)"
    }
}

/// A calendar day as a chronicle sheet has it. It is kept as text ("2026-11-21"), so the day the user chose stays
/// that day on a device in another time zone.
public enum SheetDay {
    /// The day a moment falls on where the user is.
    public static func text(of date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    /// The day as paizo.com dates a session played on it: midnight on the United States' west coast. A sheet and
    /// a session of one day then sort as the same day.
    public static func date(of text: String) -> Date? {
        date(of: text, in: paizoCalendar, hour: 0)
    }

    /// The day where the user is, at noon, for a date picker.
    public static func localDate(of text: String, calendar: Calendar = .current) -> Date? {
        date(of: text, in: calendar, hour: 12)
    }

    private static func date(of text: String, in calendar: Calendar, hour: Int) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour))
    }

    private static let paizoCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }()
}
