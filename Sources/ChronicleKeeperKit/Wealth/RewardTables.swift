import Foundation

/// The money rules of a campaign (see design.md, "Kit", for the sources).
extension CampaignRules {
    /// Whether characters of this campaign keep a ledger of gold and purchases (R5). First edition campaigns
    /// don't: the app has no item data for them and their economy is different.
    public var hasLedger: Bool {
        campaign == .pathfinder2 || campaign == .starfinder2
    }

    public var currency: Currency {
        campaign == .starfinder2 ? .credits : .gold
    }

    /// The starting funds of a new character, in copper: the lump-sum option for its starting level. Guide to
    /// Organized Play: Pathfinder Society, Character Creation ("15 gp"; 75, 270 and 720 gp at 3rd, 5th and 7th);
    /// Starfinder Society Guide, Character Creation, "Credits-Only Option" (150, 750, 2,700 and 7,200 cr).
    public func startingFunds(level: Int) -> Int {
        let table = campaign == .starfinder2 ? Self.starfinderStartingCredits : Self.pathfinderStartingGold
        let unit = campaign == .starfinder2 ? Money.copperPerCredit : Money.copperPerGold
        return (table[startingLevel(level)] ?? table[1] ?? 0) * unit
    }

    /// The amount shown as a placeholder in an adventure's gold field, in copper, for a character of this level;
    /// nil where the table has none. Pathfinder: 10 Treasure Bundles, the most an adventure gives (Guide,
    /// "Treasure Bundles", the "10 TB" column). Starfinder: the Credits Awarded table (Starfinder Society Guide,
    /// GM Basics), levels 1 to 10. Only a hint: the chronicle says what was really earned.
    public func fundsHint(level: Int) -> Int? {
        switch campaign {
        case .pathfinder2: Self.tenTreasureBundlesInSilver[level].map { $0 * Money.copperPerSilver }
        case .starfinder2: Self.creditsAwarded[level].map { $0 * Money.copperPerCredit }
        default: nil
        }
    }

    private static let pathfinderStartingGold = [1: 15, 3: 75, 5: 270, 7: 720]
    private static let starfinderStartingCredits = [1: 150, 3: 750, 5: 2_700, 7: 7_200]

    /// 10 Treasure Bundles by level, in silver pieces (14 gp at 1st level up to 36,800 gp at 20th).
    private static let tenTreasureBundlesInSilver = [
        1: 140, 2: 220, 3: 380, 4: 640, 5: 1_000, 6: 1_500, 7: 2_200, 8: 3_000, 9: 4_400, 10: 6_000,
        11: 8_600, 12: 12_400, 13: 18_800, 14: 27_400, 15: 40_800, 16: 62_000, 17: 96_000, 18: 156_000,
        19: 266_000, 20: 368_000
    ]

    private static let creditsAwarded = [
        1: 140, 2: 220, 3: 380, 4: 640, 5: 1_000, 6: 1_500, 7: 2_200, 8: 3_000, 9: 4_400, 10: 6_000
    ]
}
