import Foundation

/// The covers of the adventures a session names without a scenario number: standalone adventures, Adventure Path
/// volumes, modules, one-shots, and the intros that only a catalog numbers. The app ships with them, as paizo.com
/// and a catalog spell these names too differently to search for one by the other, and Paizo sanctions few more.
/// `scripts/update-adventure-covers.sh` rewrites the table from Warhorn's catalog.
public struct CoverTable: Sendable {
    /// One adventure as the table's file lists it, under the name and campaign code Warhorn gives it.
    struct Row: Decodable, Sendable {
        let campaign: String
        let name: String
        let cover: URL
    }

    static let resource = "adventure-covers"

    /// The table the app ships with.
    public static let bundled = CoverTable(rows: bundledRows())
    public static let empty = CoverTable(rows: [])

    private let entries: [Entry]

    init(rows: [Row]) {
        entries = rows.compactMap(Entry.init(row:))
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// The cover of the adventure whose name is most like the session's, or nothing when none is like it.
    public func cover(of adventure: AdventureEntry) -> URL? {
        let key = AdventureTitle.nameKey(adventure.title)
        var best: (cover: URL, likeness: Int)?
        for entry in entries where entry.campaign == adventure.campaign {
            let likeness = entry.likeness(toNameKey: key)
            if likeness > best?.likeness ?? 0 { best = (entry.cover, likeness) }
        }
        return best?.cover
    }

    private static func bundledRows() -> [Row] {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([Row].self, from: data)
        else { return [] }
        return rows
    }
}

/// An adventure of the table, with its name taken apart once so that looking a cover up compares only keys.
private struct Entry: Sendable {
    let campaign: Campaign
    let cover: URL
    /// The whole name's key: "menaceunderotaripart1upperlevelfrompf2beginnerbox".
    private let nameKey: String
    /// The keys of the stretches between the name's punctuation that are long enough to tell adventures apart:
    /// "menaceunderotari" and "frompf2beginnerbox".
    private let partKeys: [String]

    init?(row: CoverTable.Row) {
        guard let campaign = WarhornScenario.campaigns[row.campaign], CoverHost.isAllowed(row.cover) else {
            return nil
        }
        let title = WarhornScenario.title(from: row.name)
        self.campaign = campaign
        cover = row.cover
        nameKey = AdventureTitle.nameKey(title)
        partKeys = title.split(separator: Self.partBreakPattern)
            .map { AdventureTitle.nameKey(String($0)) }
            .filter { $0.count >= AdventureTitle.shortestNameInsideAnother }
    }

    /// How much of this adventure's name a session's name has, in letters; nothing when they aren't alike. The
    /// same name is the most alike. Otherwise the parts the session's name has count, since paizo.com names
    /// "Menace Under Otari, Part 2: Lower Level (from PF2 Beginner Box)" as "Pathfinder Beginner Box: Menace
    /// Under Otari - Lower Dungeon", and the volumes of an Adventure Path share its name but not their own.
    func likeness(toNameKey key: String) -> Int {
        if AdventureTitle.isSameKey(nameKey, key) { return Int.max }
        return partKeys.filter(key.contains).reduce(0) { $0 + $1.count }
    }

    // Regex is not Sendable, but this literal is never mutated, so sharing it is safe.

    nonisolated(unsafe) private static let partBreakPattern = /[:—–()\[\],#]|\ -\ /
}
