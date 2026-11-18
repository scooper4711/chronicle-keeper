import Foundation

/// Which factions have a symbol the app may ship: the first edition factions (not the countries) from Paizo's Community Use Package, and
/// the Pathfinder Society (2nd Edition) ones from Paizo's faction pages (paizo.com/pathfindersociety/factions).
public enum FactionArt {
    /// The symbols the app ships, by normalized name (lowercase letters and digits only).
    public static let available: Set<String> = [
        "acquisitives", "darkarchive", "dataphiles", "envoysalliance", "exoguardians",
        "grandarchive", "grandlodge", "horizonhunters", "lanternlodge", "libertysedge",
        "radiantoath", "scarabsages", "sczarni", "secondseekers", "shadowlodge", "silvercrusade",
        "sovereigncourt", "theexchange", "verdantwheel", "vigilantseal", "wayfinders"
    ]

    /// The name of the symbol for a faction as paizo.com writes it, or an empty string when there is none.
    public static func symbolName(for faction: String) -> String {
        var name = String(faction.lowercased().filter { $0.isLetter || $0.isNumber })
        if name == "exchange" { name = "theexchange" }
        return available.contains(name) ? name : ""
    }
}
