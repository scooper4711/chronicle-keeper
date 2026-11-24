import Foundation
import Testing
@testable import ChronicleKeeperKit

/// A player can rename a character on paizo.com, which renames it in every session row too: the user's corrections
/// must still find their sessions.
struct SessionOverrideTests {
    private let renamed = SessionFactory.session(characterName: "Al3x Nozama")

    @Test func aSessionsKeyLeavesOutTheCharactersName() {
        #expect(renamed.keyWithinCharacter == "1234#1")
    }

    @Test func findsACorrectionSavedUnderTheSessionsKey() {
        let settings = CharacterSettings(overrides: ["1234#1": SessionOverride(track: .slow)])
        #expect(settings.override(for: renamed)?.track == .slow)
    }

    @Test func findsACorrectionSavedUnderTheCharactersOldName() {
        let settings = CharacterSettings(overrides: ["1234#1#PF Coop 333": SessionOverride(track: .slow)])
        #expect(settings.override(for: renamed)?.track == .slow)
        let progress = ProgressCalculator(campaign: .pathfinder2).progress(of: renamed, settings: settings)
        #expect(progress.trackSource == .override)
    }

    @Test func ignoresAnotherSessionsCorrection() {
        let settings = CharacterSettings(overrides: ["1234#12#PF Coop 333": SessionOverride(track: .slow)])
        #expect(settings.override(for: renamed) == nil)
    }

    @Test func olderNamesGiveTheSameCorrectionEveryTime() {
        let settings = CharacterSettings(overrides: [
            "1234#1#Zed": SessionOverride(track: .normal), "1234#1#PF Coop 333": SessionOverride(track: .slow)
        ])
        #expect(settings.override(for: renamed)?.track == .slow)
    }

    @Test func aCorrectionUnderTheSessionsKeyWinsOverAnOlderName() {
        let settings = CharacterSettings(overrides: [
            "1234#1": SessionOverride(track: .normal), "1234#1#PF Coop 333": SessionOverride(track: .slow)
        ])
        #expect(settings.override(for: renamed)?.track == .normal)
    }

    @Test func aCorrectionMadeOnAnOlderVersionWins() {
        // This version writes both keys alike, so a difference means a 1.0.0 device changed the ID's since.
        let settings = CharacterSettings(overrides: [
            "1234#1": SessionOverride(track: .normal), renamed.id: SessionOverride(track: .slow)
        ])
        #expect(settings.override(for: renamed)?.track == .slow)
    }

    @Test func savingACorrectionKeepsItWhereAnOlderVersionLooks() {
        var settings = CharacterSettings(overrides: ["1234#1#PF Coop 333": SessionOverride(track: .slow)])
        settings.setOverride(SessionOverride(track: .normal), for: renamed)
        #expect(settings.overrides["1234#1"]?.track == .normal)
        #expect(settings.overrides[renamed.id]?.track == .normal)
        #expect(settings.override(for: renamed)?.track == .normal)
    }

    @Test func savingNoCorrectionRemovesIt() {
        var settings = CharacterSettings()
        settings.setOverride(SessionOverride(track: .slow), for: renamed)
        settings.setOverride(nil, for: renamed)
        #expect(settings.overrides.isEmpty)
    }
}
