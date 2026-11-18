import Foundation

/// Merges a character's settings changed on two devices (plan, "iCloud sync"): against the copy both last agreed
/// on, a field changed here wins, otherwise the other device's value stands. Track overrides merge per session, so
/// an override set on the iPad and a note typed on the Mac both survive.
public enum SettingsMerge {
    public static func merge(
        local: CharacterSettings, remote: CharacterSettings, ancestor: CharacterSettings
    ) -> CharacterSettings {
        var merged = remote
        merged.defaultTrack = pick(local.defaultTrack, remote.defaultTrack, ancestor.defaultTrack)
        merged.xpAdjustment = pick(local.xpAdjustment, remote.xpAdjustment, ancestor.xpAdjustment)
        merged.notes = pick(local.notes, remote.notes, ancestor.notes)
        merged.portraitFileName = pick(local.portraitFileName, remote.portraitFileName, ancestor.portraitFileName)
        merged.characterSheetLink =
            pick(local.characterSheetLink, remote.characterSheetLink, ancestor.characterSheetLink)
        merged.overrides = mergeOverrides(local.overrides, remote.overrides, ancestor.overrides)
        return merged
    }

    /// The local value when it changed since the ancestor, otherwise the remote one.
    static func pick<Value: Equatable>(_ local: Value, _ remote: Value, _ ancestor: Value) -> Value {
        local == ancestor ? remote : local
    }

    private static func mergeOverrides(
        _ local: [String: SessionOverride], _ remote: [String: SessionOverride], _ ancestor: [String: SessionOverride]
    ) -> [String: SessionOverride] {
        let keys = Set(local.keys).union(remote.keys).union(ancestor.keys)
        var merged: [String: SessionOverride] = [:]
        for key in keys {
            let override = pick(local[key], remote[key], ancestor[key])
            // An override with nothing set is the same as none.
            if let override, override != SessionOverride() { merged[key] = override }
        }
        return merged
    }
}
