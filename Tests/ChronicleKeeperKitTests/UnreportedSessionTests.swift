import Foundation
import Testing
@testable import ChronicleKeeperKit

/// A chronicle sheet added before paizo.com lists its session counts as a session (R1.14).
struct UnreportedSessionTests {
    private func valeria(_ sheets: [String: SheetReading], sessions: [PlayedSession]? = nil) -> CharacterRecord {
        let roster = sessions.map { UnreportedFactory.roster(sheets: sheets, sessions: $0) }
            ?? UnreportedFactory.roster(sheets: sheets)
        return roster.characters[0]
    }

    @Test func aSheetIsASessionOfItsCharacterMarkedAsUnreported() throws {
        let record = valeria(["a": UnreportedFactory.reading()])
        let unreported = try #require(record.sessions.first)
        #expect(record.sessions.count == 2)
        #expect(record.unreportedCount == 1)
        #expect(!unreported.isReported)
        #expect(unreported.id == "unreported/a")
        #expect(unreported.session.keyWithinCharacter == "unreported/a")
        #expect(unreported.session.adventure.title == "#6-05")
        #expect(unreported.session.characterNumber == UnreportedFactory.valeria)
        #expect(unreported.kind == .scenario)
        #expect(record.sessions[1].isReported)
        #expect(record.sessions[1].session.keyWithinCharacter == "1234#1")
    }

    @Test func itsXPCountsTowardTheLevelRightAway() {
        let sheets = ["a": UnreportedFactory.reading(), "b": UnreportedFactory.reading(code: "6-06")]
        let record = valeria(sheets)
        #expect(record.level.xp == 12)
        #expect(record.level.level == 2)
        #expect(record.sessions[0].xpSource == .chronicle)
    }

    @Test func aSheetWithoutXPGetsItsKindsNormalXPOnTheDefaultTrack() throws {
        let record = valeria(["a": UnreportedFactory.reading { $0.xp = nil }])
        let unreported = try #require(record.sessions.first)
        #expect(unreported.xp == 4)
        #expect(unreported.xpSource == .rules)
        #expect(unreported.trackSource == .characterDefault)
    }

    @Test func halfTheXPMeansSlowTrack() throws {
        let unreported = try #require(valeria(["a": UnreportedFactory.reading { $0.xp = 2 }]).sessions.first)
        #expect(unreported.track == .slow)
        #expect(unreported.trackSource == .chronicle)
    }

    @Test func itIsDatedOnTheDayPlayedOrElseTheDayItWasAdded() throws {
        let played = try #require(valeria(["a": UnreportedFactory.reading()]).sessions.first)
        #expect(played.date.day == SheetDay.date(of: "2026-06-01"))
        #expect(!played.date.isInferred)
        let added = try #require(valeria(["a": UnreportedFactory.reading { $0.playedOn = nil }]).sessions.first)
        #expect(added.date.day == Date(timeIntervalSince1970: 1_780_400_000))
    }

    @Test func anotherCharactersSessionOfTheAdventureGivesItsNameAndLevels() throws {
        let pips = UnreportedFactory.pipsSession("#6-05: Ashes Over Highhelm", eventCode: "9")
        let record = valeria(["a": UnreportedFactory.reading()], sessions: [SessionFactory.session(), pips])
        let unreported = try #require(record.sessions.first)
        #expect(unreported.session.adventure.titleWithLevels == "#6-05: Ashes Over Highhelm (1–4)")
        #expect(unreported.session.adventure.productID == pips.adventure.productID)
    }

    /// The name and levels a catalog gave: a sheet played below its adventure's levels is held like any session.
    @Test func aSheetOfAnAdventureAboveTheCharactersLevelIsHeld() throws {
        let named = UnreportedFactory.reading {
            $0.title = "#6-05: Ashes Over Highhelm"
            $0.levels = LevelRange(lowest: 5, highest: 8)
        }
        let record = valeria(["a": named])
        let unreported = try #require(record.sessions.first)
        #expect(unreported.session.adventure.titleWithLevels == "#6-05: Ashes Over Highhelm (5–8)")
        #expect(unreported.isOutOfLevelRange)
        #expect(unreported.xpLost == 4)
        #expect(record.level.xp == 4)
    }

    @Test func aSheetWithoutANumberStillShows() throws {
        let unreported = try #require(valeria(["a": UnreportedFactory.reading(code: nil)]).sessions.first)
        #expect(unreported.session.adventure.title == "Chronicle Sheet")
        #expect(unreported.kind == .other)
    }

    @Test func theSheetAddedLastIsListedFirstAmongSheetsOfOneDay() {
        let dayBefore = Date(timeIntervalSince1970: 1_780_300_000)
        let earlier = UnreportedFactory.reading(code: "6-06") { $0.addedAt = dayBefore }
        let record = valeria(["z": earlier, "a": UnreportedFactory.reading()])
        #expect(record.sessions.map(\.id) == ["unreported/a", "unreported/z", "1234#1#Valeria Stonebrook"])
    }

    @Test func aReadingKeptForAReportedSessionMakesNoSession() {
        var settings = CharacterSettings()
        settings.wealth.sheetReadings["1234#1"] = UnreportedFactory.reading(code: "6-04")
        let roster = CharacterRoster(
            summaries: UnreportedFactory.characters, sessions: [SessionFactory.session()],
            settings: [UnreportedFactory.valeria: settings])
        #expect(roster.characters[0].sessions.count == 1)
        #expect(roster.characters[0].unreportedCount == 0)
    }

    // MARK: - What counts it

    @Test func itCountsAsPlayedInWhoCanPlay() {
        let record = valeria(["a": UnreportedFactory.reading()])
        let adventure = AdventureEntry(published: Covers.published("#6-05: Ashes Over Highhelm"))
        #expect(AdventureFinder.eligibility(of: record, for: adventure)
            == .alreadyPlayed(SessionDate(day: SheetDay.date(of: "2026-06-01"))))
    }

    /// paizo.com hands a reward out only for a session it has.
    @Test func itEarnsNoRewardToClaim() throws {
        let unreported = valeria(["a": UnreportedFactory.reading(code: "6-03")], sessions: [])
        #expect(try RewardFactory.eligibility().claimable(for: unreported, owned: []).isEmpty)
        let reported = RewardFactory.record(playing: ["#6-03: Godsrain in a Godless Land"])
        #expect(try RewardFactory.eligibility().claimable(for: reported, owned: []).count == 1)
    }

    @Test func itsGoldAndThePurchasesAfterItAreInTheLedger() throws {
        var settings = UnreportedFactory.settings(["a": UnreportedFactory.reading()])
        settings.wealth.earned["unreported/a"] = 1_400
        settings.wealth.add(Purchase(name: "Rope", unitPrice: 50, boughtAfter: "unreported/a"))
        let roster = CharacterRoster(
            summaries: UnreportedFactory.characters, sessions: [SessionFactory.session()],
            settings: [UnreportedFactory.valeria: settings])
        let ledger = WealthLedger(record: roster.characters[0])
        let group = try #require(ledger.groups.last)
        #expect(group.id == "unreported/a")
        #expect(group.lines.map(\.amount) == [1_400, -50])
        #expect(ledger.balance == 1_500 + 1_400 - 50)
        #expect(ledger.adventuresWithoutGold == 1)
    }

    // MARK: - Storage

    @Test func whatMakesTheSessionIsSavedWithTheReadingAndReadBack() throws {
        let reading = UnreportedFactory.reading {
            $0.title = "#6-05: Ashes Over Highhelm"
            $0.levels = LevelRange(lowest: 1, highest: 4)
            $0.pendingFile = "123456-2001/a"
        }
        let saved = try JSONEncoder().encode(reading)
        #expect(try JSONDecoder().decode(SheetReading.self, from: saved) == reading)
    }

    @Test func aReadingFromBeforeUnreportedSheetsHasNoneOfIt() throws {
        let saved = Data(#"{"source": "pdfText", "clearedWarnings": [], "xp": 4}"#.utf8)
        let reading = try JSONDecoder().decode(SheetReading.self, from: saved)
        #expect(reading.xp == 4)
        #expect(reading.title == nil && reading.levels == nil && reading.playedOn == nil)
        #expect(reading.addedAt == nil && reading.pendingFile == nil)
    }

    // MARK: - Keys, days and words

    @Test func aKeyNamesItsSheet() {
        #expect(UnreportedSheet.key("a") == "unreported/a")
        #expect(UnreportedSheet.id(ofKey: "unreported/a") == "a")
        #expect(UnreportedSheet.id(ofKey: "1234#1") == nil)
    }

    /// paizo.com dates a session at midnight on the United States' west coast.
    @Test func aDayIsTheSameMomentAsPaizosDateForIt() {
        #expect(SheetDay.date(of: "2024-05-25") == ISO8601DateFormatter().date(from: "2024-05-25T07:00:00Z"))
        #expect(SheetDay.date(of: "2026-01-15") == ISO8601DateFormatter().date(from: "2026-01-15T08:00:00Z"))
        #expect(SheetDay.date(of: "soon") == nil)
    }

    @Test func aDayIsWrittenAsTheUserSeesItAndReadBack() throws {
        var oslo = Calendar(identifier: .gregorian)
        oslo.timeZone = try #require(TimeZone(identifier: "Europe/Oslo"))
        let lateEvening = try #require(ISO8601DateFormatter().date(from: "2026-11-21T22:30:00Z"))
        #expect(SheetDay.text(of: lateEvening, calendar: oslo) == "2026-11-21")
        let noon = try #require(SheetDay.localDate(of: "2026-11-21", calendar: oslo))
        #expect(SheetDay.text(of: noon, calendar: oslo) == "2026-11-21")
        #expect(oslo.component(.hour, from: noon) == 12)
    }

    @Test func aRangesSummaryReadsBackAsTheRange() {
        for range in [LevelRange(lowest: 1, highest: 4), LevelRange(lowest: 5, highest: 5)] {
            let adventure = AdventureReference(productID: "", title: "#1-01", summary: range.summaryText)
            #expect(AdventureClassifier.levelRange(of: adventure) == range)
        }
    }

    @Test func theWordsSayWhatIsUnreported() {
        let added = Date(timeIntervalSince1970: 1_780_400_000)
        let day = added.formatted(.dateTime.day().month(.abbreviated))
        #expect(UnreportedText.caption(added: added) == "Not reported yet · added \(day)")
        #expect(UnreportedText.caption(added: nil) == "Not reported yet")
        #expect(UnreportedText.adventuresTitle(of: valeria([:])) == "Adventures (1)")
        #expect(UnreportedText.adventuresTitle(of: valeria(["a": UnreportedFactory.reading()]))
            == "Adventures (2 · 1 not reported)")
        #expect(UnreportedText.totalsNote(count: 0).isEmpty)
        #expect(UnreportedText.totalsNote(count: 1) == "Includes 1 session paizo.com doesn't have yet")
        #expect(UnreportedText.totalsNote(count: 3) == "Includes 3 sessions paizo.com doesn't have yet")
        #expect(UnreportedText.elsewhere(adventure: "#6-05", character: "Pip").contains("for Pip"))
    }

    @Test func removingSaysWhatHappensToThePurchasesAndWhetherItCanBeAttached() {
        let plain = UnreportedText.removalMessage(purchases: 0, canAttach: false)
        #expect(!plain.contains("purchase"))
        #expect(!plain.contains("attach"))
        #expect(UnreportedText.removalMessage(purchases: 1, canAttach: false).contains("The purchase made after it"))
        let full = UnreportedText.removalMessage(purchases: 2, canAttach: true)
        #expect(full.contains("The 2 purchases made after it"))
        #expect(full.contains("attach the sheet"))
    }
}
