import ChronicleKeeperKit

/// Reads an item's price from a pf2e document's `system.price`, as copper pieces (a Starfinder credit is 1 sp).
enum ItemPrice {
    /// The price of one batch in copper, or nil when the item has no price in coins or credits.
    static func copper(_ price: PackValue, game: ItemGame) -> Int? {
        let value = price["value"]
        let copper = game == .starfinder ? credits(value) : coins(value)
        return copper > 0 ? copper : nil
    }

    /// How many items one price buys (ammunition and the like); 1 when the document says nothing.
    static func batchSize(_ price: PackValue) -> Int {
        max(price["per"].int, 1)
    }

    private static func coins(_ value: PackValue) -> Int {
        value["pp"].int * 1000 + value["gp"].int * 100 + value["sp"].int * 10 + value["cp"].int
    }

    /// Starfinder keeps credits as silver pieces. UPBs (universal polymer bonds) are no coin, so they add nothing.
    private static func credits(_ value: PackValue) -> Int {
        (value["pp"].int * 100 + value["gp"].int * 10 + value["sp"].int + value["credits"].int) * 10
    }
}
