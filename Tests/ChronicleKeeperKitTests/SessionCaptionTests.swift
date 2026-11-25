import Testing
@testable import ChronicleKeeperKit

struct SessionCaptionTests {
    private let pathfinder = ProgressCalculator(campaign: .pathfinder2)

    /// A 1st-level character's session: in its level range by default, held (3rd–4th) when `held`.
    private func progress(reputation: Double?, xp: Double? = nil, held: Bool = false) throws -> SessionProgress {
        let session = held
            ? SessionFactory.session(
                title: "#6-04: A Mid-Tier Scenario",
                summary: "A Pathfinder Society Scenario designed for 3rd- through 4th-level characters",
                reputation: reputation)
            : SessionFactory.session(reputation: reputation)
        var settings = CharacterSettings()
        if let xp { settings.overrides[session.keyWithinCharacter] = SessionOverride(xp: xp) }
        return try #require(pathfinder.history(of: [session], settings: settings).first)
    }

    @Test func theCaptionNamesTheKindXPAndReputation() throws {
        let caption = SessionCaption.text(for: try progress(reputation: 4), showsReputation: true)
        #expect(caption == "Scenario · 4 XP · 4 Rep")
    }

    @Test func noReputationIsLeftOut() throws {
        let withoutReputation = try progress(reputation: nil, xp: 4)
        #expect(SessionCaption.text(for: withoutReputation, showsReputation: true) == "Scenario · 4 XP")
        #expect(SessionCaption.text(for: try progress(reputation: 4), showsReputation: false) == "Scenario · 4 XP")
    }

    @Test func lostXPFollowsTheXP() throws {
        let caption = SessionCaption.text(for: try progress(reputation: 4, xp: 50, held: true), showsReputation: true)
        #expect(caption == "Scenario · 50 XP (50 lost) · 4 Rep")
    }

    @Test func halvesKeepOneDecimal() {
        #expect(XPText.of(2.5) == 2.5.formatted(.number.precision(.fractionLength(1))))
        #expect(XPText.of(4) == "4")
    }
}
