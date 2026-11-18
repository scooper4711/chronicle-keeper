import Testing
@testable import CharacterKeeperKit

struct AdventureClassifierTests {
    private func adventure(_ title: String, _ summary: String = "") -> AdventureReference {
        AdventureReference(productID: "", title: title, summary: summary)
    }

    @Test(arguments: [
        ("A Pathfinder Society Scenario designed for 1st- through 4th-level characters", AdventureKind.scenario),
        ("A Pathfinder Society Special designed for 1st- through 8th-level characters", .scenario),
        ("A Pathfinder Society Quest designed for levels 1-4 (Subtiers 1-2 and 3-4)", .questSeries1),
        ("A Pathfinder Bounty designed for 1st-level characters", .bounty),
        ("A Starfinder Society Scenario designed for 1st- through 2nd-level characters", .scenario)
    ])
    func kindFromTheSummary(summary: String, kind: AdventureKind) {
        #expect(AdventureClassifier.kind(of: adventure("Anything", summary)) == kind)
    }

    @Test(arguments: [
        ("#5-19: Demonic Afterparty", AdventureKind.scenario),
        ("Intro: Year of Boundless Wonder", .scenario),
        ("Pathfinder Bounty #19: Grim Tidings", .bounty),
        ("Pathfinder Quest (Series 2) #15: Something", .questSeries2),
        ("Quest #14: Something", .questSeries2),
        ("Quest #3: Something", .questSeries1),
        ("Some Adventure Path Volume", .adventure),
        ("Starfinder Free RPG Day", .other)
    ])
    func kindFromTheTitle(title: String, kind: AdventureKind) {
        #expect(AdventureClassifier.kind(of: adventure(title)) == kind)
    }

    @Test func seriesTwoQuestSummaryKeepsTheSeriesFromTheTitle() {
        let quest = adventure("Pathfinder Quest (Series 2) #15", "A Pathfinder Society Quest designed for levels 1-4")
        #expect(AdventureClassifier.kind(of: quest) == .questSeries2)
    }

    @Test(arguments: [
        ("designed for 1st- through 4th-level characters", 1, 4),
        ("designed for 7th- through 10th-level characters", 7, 10),
        ("designed for levels 1–8 (subtiers 1-2, 3-6, 7-8)", 1, 8),
        ("designed for levels 3–6 (subtiers 3–4 and 5–6)", 3, 6),
        ("A Pathfinder Bounty designed for 3rd-level characters", 3, 3)
    ])
    func levelRange(summary: String, lowest: Int, highest: Int) {
        let range = AdventureClassifier.levelRange(of: adventure("", summary))
        #expect(range == LevelRange(lowest: lowest, highest: highest))
    }

    @Test(arguments: [
        ("#5-19: Demonic Afterparty", "designed for levels 3–7 (subtiers 3–4 and 5–7)",
         "#5-19: Demonic Afterparty (3–7)"),
        ("Pathfinder Bounty #19: Wake", "A Pathfinder Bounty designed for 1st-level characters",
         "Pathfinder Bounty #19: Wake (1)"),
        ("Starfinder Free RPG Day", "", "Starfinder Free RPG Day")
    ])
    func titleWithLevels(title: String, summary: String, expected: String) {
        #expect(adventure(title, summary).titleWithLevels == expected)
    }

    @Test func noLevelRangeWithoutADescription() {
        #expect(AdventureClassifier.levelRange(of: adventure("Starfinder Free RPG Day")) == nil)
    }

    @Test(arguments: [
        ("PFS(2ed) #7-16: A Star's Journey", "7-16"),
        ("Starfinder Society Scenario #1-10: Rites", "1-10"),
        ("Pathfinder Quest (Series 2) #15: Name", "Quest 15"),
        ("Pathfinder Bounty #19: Grim Tidings", "Bounty 19")
    ])
    func code(title: String, code: String) {
        #expect(AdventureClassifier.code(of: adventure(title)) == code)
    }
}
