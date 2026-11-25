import Foundation

/// Merges a character's ledger changed on two devices, as `SettingsMerge` does the rest: the gold of each adventure
/// and each purchase merge on their own, so a purchase added on the iPad and one added on the Mac both survive.
/// Within one purchase, the copy changed here wins whole.
public enum WealthMerge {
    public static func merge(
        local: CharacterWealth, remote: CharacterWealth, ancestor: CharacterWealth
    ) -> CharacterWealth {
        var merged = CharacterWealth(
            startingFunds: SettingsMerge.pick(local.startingFunds, remote.startingFunds, ancestor.startingFunds),
            earned: perKey(local.earned, remote.earned, ancestor.earned),
            purchases: perKey(local.purchases, remote.purchases, ancestor.purchases))
        merged.unknownFields = SettingsMerge.pick(local.unknownFields, remote.unknownFields, ancestor.unknownFields)
        return merged
    }

    /// Each key on its own: the local value when it changed since the ancestor (added, edited or removed),
    /// otherwise the remote one.
    private static func perKey<Value: Equatable>(
        _ local: [String: Value], _ remote: [String: Value], _ ancestor: [String: Value]
    ) -> [String: Value] {
        let keys = Set(local.keys).union(remote.keys).union(ancestor.keys)
        var merged: [String: Value] = [:]
        for key in keys {
            merged[key] = SettingsMerge.pick(local[key], remote[key], ancestor[key])
        }
        return merged
    }
}
