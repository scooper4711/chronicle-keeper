import Foundation

/// Free rewards for the demo account to find waiting, worded the way paizo.com words its own. The chronicle boons
/// are made up, as the demo's adventures are.
public enum DemoRewards {
    /// The demo's lists never change, so they are read once per run.
    public struct Source: RewardCatalogSource {
        public init() {}

        public func rewardCatalog() async throws -> RewardCatalog {
            RewardCatalog(offers: DemoRewards.offers, fetchedAt: Date())
        }
    }

    static var offers: [RewardOffer] {
        chronicleBoons + gameRewards
    }

    /// Valeria played both adventures: one boon, and one adventure whose Chronicle Sheet says which boon she earned.
    private static var chronicleBoons: [RewardOffer] {
        offers(of: "Chronicle Boons - PFS(2ed)", [
            ("PFS (2ed) Scenario #6-05: Ashes Over Highhelm Boon A",
             "Ember Friend: the keepers of the forge remember your help. A made-up boon."),
            ("PFS (2ed) Scenario #6-05: Ashes Over Highhelm Boon B",
             "Ash Walker: the keepers of the forge remember what you let burn. A made-up boon."),
            ("PFS (2ed) Scenario #6-09: Glass Sea Pearl",
             "A made-up boon: hold your breath for a whole scene. "
                + "Must have played PFS2 #6-09: Tides of the Glass Sea to download.")
        ])
    }

    /// Valeria and Zenobia are Liked by the Horizon Hunters, Zenobia is Admired, and Pip has played two sessions.
    private static var gameRewards: [RewardOffer] {
        offers(of: "Game Rewards - PFS(2ed)", [
            ("Skillful Mentor (Envoy's Alliance)",
             "Help low-level PCs at your table with skill checks. Must be Liked by Envoy's Alliance to obtain."),
            ("Rugged Mentor (Horizon Hunters)",
             "Help low-level PCs at your table with saving throws. Must be Liked by Horizon Hunters to obtain."),
            ("Heroic Hustle (Horizon Hunters)",
             "Gain extra movement speed when spending Hero Points to reroll. "
                + "Must be Admired by Horizon Hunters to obtain."),
            ("Wayfinder", "Gain a free wayfinder. Character must have played 2 sessions to obtain.")
        ]) + offers(of: "Game Rewards - SFS", [
            ("Purveyor of Fortunes (Acquisitives)",
             "Gain extra Reputation for participating in the Retail Incentive Program. "
                + "Must have at least 5 Reputation with the Acquisitives to obtain.")
        ])
    }

    private static func offers(of pointType: String, _ rows: [(name: String, summary: String)]) -> [RewardOffer] {
        guard let type = RewardPointType(pointType) else { return [] }
        return rows.map { RewardOffer(type: type, name: $0.name, summary: $0.summary) }
    }
}
