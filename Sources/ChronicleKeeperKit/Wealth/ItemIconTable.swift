import Foundation

/// Which icon file each item has: the table `scripts/item-icons.py` writes from Field Guide's icon choices, one
/// "item id, Rexard picture, icon file" row per item, after a header. Items without a row have no icon.
public struct ItemIconTable: Sendable {
    private let icons: [String: String]

    public init(tsv: String) {
        var icons: [String: String] = [:]
        for row in tsv.split(whereSeparator: \.isNewline).dropFirst() {
            let columns = row.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count == 3, !columns[0].isEmpty, !columns[2].isEmpty else { continue }
            icons[String(columns[0])] = String(columns[2])
        }
        self.icons = icons
    }

    /// The icon file of the item with `itemID`; nil for a custom item or one without an icon.
    public func icon(for itemID: String) -> String? {
        itemID.isEmpty ? nil : icons[itemID]
    }

    public var count: Int { icons.count }
}
