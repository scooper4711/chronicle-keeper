import Foundation

/// Made-up ledgers for the demo characters (R5): gold entered for some adventures and left empty for others, a
/// purchase above the character's level, one sold and one linked to a boon, and the gold of a session paizo.com
/// doesn't list yet, so every kind of ledger line shows.
public enum DemoWealth {
    /// The demo characters' settings, holding their ledgers.
    public static var settings: [String: CharacterSettings] {
        [
            "\(DemoAccount.playerNumber)-2001": settings(with: valeria),
            "\(DemoAccount.playerNumber)-2002": settings(with: pip),
            "\(DemoAccount.playerNumber)-701": settings(with: zix)
        ]
    }

    private static func settings(with wealth: CharacterWealth) -> CharacterSettings {
        var settings = CharacterSettings()
        settings.wealth = wealth
        return settings
    }

    /// Gold for her first four adventures, and for the newest from its chronicle sheet; a Healing Potion (Lesser)
    /// (level 3) bought at level 1 is marked, and her leather armor is sold once she buys chain mail.
    private static var valeria: CharacterWealth {
        let gold = Money.copperPerGold
        var potions = item("Healing Potion (Minor)", level: 1, price: 4 * gold, after: "")
        potions.quantity = 2
        var armor = item("Leather Armor", level: 0, price: 2 * gold, after: "")
        armor.soldAfter = "9004#4"
        var wealth = ledger(
            earned: [
                "9001#1": 14 * gold, "9002#2": 20 * gold, "9003#3": 7 * gold, "9004#4": 38 * gold,
                DemoChronicles.sessionKey: DemoChronicles.reading.funds ?? 0
            ],
            purchases: [
                item("Longsword", level: 0, price: 1 * gold, after: ""), armor, potions,
                item("Healing Potion (Lesser)", level: 3, price: 12 * gold, after: "9001#1"),
                item("Chain Mail", level: 1, price: 6 * gold, after: "9004#4")
            ])
        wealth.sheetReadings[DemoChronicles.sessionKey] = DemoChronicles.reading
        return wealth
    }

    /// Only the chronicle sheet of a session paizo.com doesn't list yet, with its gold (R1.14).
    private static var pip: CharacterWealth {
        var wealth = CharacterWealth(
            earned: [DemoChronicles.unreportedKey: DemoChronicles.unreportedReading.funds ?? 0])
        wealth.sheetReadings[DemoChronicles.unreportedKey] = DemoChronicles.unreportedReading
        return wealth
    }

    /// Credits for his first adventure; an uncommon item that his boon gives Access to, so it has a check (R5.10).
    private static var zix: CharacterWealth {
        let credit = Money.copperPerCredit
        var medpatches = item("Medpatch", level: 0, price: 5 * credit, after: "")
        medpatches.quantity = 3
        var drone = item("Holo-Skin Drone", level: 1, price: 120 * credit, after: "9009#9")
        drone.rarity = .uncommon
        drone.accessLink = DemoBoons.boons.first { $0.name == "Drift Beacon" }.map(AccessLink.init(boon:))
        return ledger(
            earned: ["9009#9": 140 * credit],
            purchases: [item("Laser Pistol", level: 0, price: 50 * credit, after: ""), medpatches, drone])
    }

    /// A ledger whose purchases were added in the order given, a second apart.
    private static func ledger(earned: [String: Int], purchases: [Purchase]) -> CharacterWealth {
        var wealth = CharacterWealth(earned: earned)
        for (index, purchase) in purchases.enumerated() {
            var added = purchase
            added.addedAt = Date(timeIntervalSince1970: 1_795_000_000 + Double(index))
            wealth.add(added)
        }
        return wealth
    }

    private static func item(_ name: String, level: Int, price: Int, after key: String) -> Purchase {
        Purchase(id: "demo-\(name.lowercased().filter(\.isLetter))", itemID: catalogIDs[name] ?? "", name: name,
                 level: level, unitPrice: price, boughtAfter: key)
    }

    /// The item data's ids of the demo's items, so they show their icons as a real purchase does.
    private static let catalogIDs = [
        "Longsword": "pf2e/LJdbVTOZog39EEbi", "Leather Armor": "pf2e/4tIVTg9wj56RrveA",
        "Chain Mail": "pf2e/Kf4eJEXnFPuAsseP", "Healing Potion (Minor)": "pf2e/2RuepCemJhrpKKao",
        "Healing Potion (Lesser)": "pf2e/e0vSAQfxhHauiAoD", "Laser Pistol": "sf2e/qIgcUV22LaDCzmb2"
    ]
}
