import Foundation
import Testing
@testable import CharacterKeeperKit

@Suite("Model names and codes")
struct ModelNamesTests {
    @Test(arguments: [
        ("PFS", Campaign.pathfinder1), ("pfs(1ed)", .pathfinder1), ("PFS(2ed)", .pathfinder2),
        ("PFS2", .pathfinder2), ("SFS", .starfinder1), ("SFS(1ED)", .starfinder1),
        ("SFS2", .starfinder2), ("SFS(2ed)", .starfinder2), (" XYZ ", .other("XYZ"))
    ])
    func readsCampaignCodes(code: String, expected: Campaign) {
        #expect(Campaign(code: code) == expected)
    }

    @Test func campaignsHaveNamesAndAnOrder() {
        let campaigns: [Campaign] = [.pathfinder2, .starfinder2, .pathfinder1, .starfinder1, .other("XYZ")]
        #expect(campaigns.map(\.sortOrder) == [0, 1, 2, 3, 4])
        #expect(campaigns.map(\.shortName) == ["PFS2", "SFS2", "PFS1", "SFS1", "XYZ"])
        #expect(campaigns.map(\.displayName).allSatisfy { !$0.isEmpty })
        #expect(Campaign.other("XYZ").displayName == "XYZ")
    }

    @Test func adventureKindsHaveNames() {
        #expect(AdventureKind.allCases.map(\.displayName) ==
            ["Scenario", "Quest", "Quest", "Bounty", "Adventure", "Other"])
        #expect(AdventureKind.bounty.isRepeatable)
        #expect(!AdventureKind.scenario.isRepeatable)
    }

    @Test func levelRangesReadAsText() {
        let range = LevelRange(lowest: 7, highest: 3)
        #expect(range.displayText == "Levels 3–7")
        #expect(range.shortText == "3–7")
        #expect(LevelRange(lowest: 1, highest: 1).displayText == "Level 1")
        #expect(LevelRange(lowest: 1, highest: 1).shortText == "1")
    }

    @Test func tracksScaleRewards() {
        #expect(Track.slow.rewardFactor == 0.5)
        #expect(Track.normal.rewardFactor == 1)
        #expect(Track.allCases.map(\.displayName) == ["Normal", "Slow"])
    }
}

@Suite("Faction art")
struct FactionArtTests {
    @Test func findsSymbolsByFactionName() {
        #expect(FactionArt.symbolName(for: "Liberty's Edge") == "libertysedge")
        #expect(FactionArt.symbolName(for: "Exchange") == "theexchange")
        #expect(FactionArt.symbolName(for: "Exo-Guardians") == "exoguardians")
        #expect(FactionArt.symbolName(for: "Horizon Hunters") == "horizonhunters")
        #expect(FactionArt.symbolName(for: "Envoy's Alliance") == "envoysalliance")
        #expect(FactionArt.symbolName(for: "Unknown Faction").isEmpty)
    }

    @Test func everyAvailableSymbolIsShipped() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/CharacterKeeperUI/Resources/Factions")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(Set(files.map { ($0 as NSString).deletingPathExtension }) == FactionArt.available)
    }
}
